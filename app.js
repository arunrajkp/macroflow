// ============================================================
//  MacroFlow – Supabase App Helper (app.js)
//  Shared across all pages via <script src="app.js">
// ============================================================

// ── Supabase Project Config ──────────────────────────────────
const SUPABASE_URL = 'https://zfovszmjrtmerasczmsc.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_AIKgg9Q7wtNc9jgNBCWmEA_vGNEZREF';
// ─────────────────────────────────────────────────────────────

let _sb = null;
try {
    if (typeof supabase !== 'undefined') {
        _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: true
            }
        });
    } else {
        console.error('Supabase library not found!');
    }
} catch (e) {
    console.error('Core Init Failed:', e);
}

// ── Auth helpers ─────────────────────────────────────────────
async function getUser() {
    if (!_sb) return null;
    try {
        const { data: { session } } = await _sb.auth.getSession();
        return session ? session.user : null;
    } catch (e) {
        console.warn('Auth check skipped:', e);
        return null;
    }
}

async function requireAuth() {
    try {
        const user = await getUser();
        if (!user) {
            // Check if we're already on index.html to avoid loop
            if (!window.location.pathname.endsWith('index.html') && window.location.pathname !== '/') {
                window.location.href = 'index.html';
            }
            return null;
        }
        return user;
    } catch (e) {
        console.error('Auth requirement failed:', e);
        return null;
    }
}

async function signIn(email, password) {
    if (!_sb) return { error: { message: 'Supabase client not initialized.' } };
    return _sb.auth.signInWithPassword({ email, password });
}

async function signUp(email, password, username, fullName) {
    if (!_sb) return { error: { message: 'Supabase client not initialized.' } };
    return _sb.auth.signUp({
        email, password,
        options: { data: { username, full_name: fullName } }
    });
}

async function signOut() {
    if (_sb) await _sb.auth.signOut();
    window.location.href = 'index.html';
}

// ── Profile ──────────────────────────────────────────────────
async function getProfile(userId) {
    if (!_sb) return { data: null, error: 'No SB' };
    return await _sb.from('profiles').select('*').eq('id', userId).single();
}

async function updateProfile(userId, updates) {
    if (!_sb) return { error: 'No SB' };
    return await _sb.from('profiles').update(updates).eq('id', userId);
}

async function uploadAvatar(userId, file) {
    if (!_sb) return { error: 'No SB' };

    const fileExt = file.name.split('.').pop();
    const fileName = `${userId}-${Math.random()}.${fileExt}`;
    const filePath = `${userId}/${fileName}`;

    // 1. Upload file to 'avatars' bucket
    const { error: uploadError } = await _sb.storage
        .from('avatars')
        .upload(filePath, file);

    if (uploadError) return { error: uploadError };

    // 2. Get public URL
    const { data: { publicUrl } } = _sb.storage
        .from('avatars')
        .getPublicUrl(filePath);

    // 3. Update profile with new URL
    return await updateProfile(userId, { avatar_url: publicUrl });
}

function calculateHealthMetrics(p) {
    if (!p || !p.weight_kg || !p.height_cm) return null;
    const hM = p.height_cm / 100;
    const bmi = p.weight_kg / (hM * hM);

    // Deurenberg formula for Body Fat %: (1.20 × BMI) + (0.23 × Age) - (10.8 × Gender) - 5.4
    let bf = 0;
    if (p.age && p.gender) {
        const gVal = p.gender === 'male' ? 1 : 0;
        bf = (1.20 * bmi) + (0.23 * p.age) - (10.8 * gVal) - 5.4;
    }

    // Protein Target: 1.8g - 2.0g per kg of body weight
    const proteinTarget = Math.round(p.weight_kg * 1.8);
    const kcalTarget = Math.round(p.weight_kg * 30); // Rough TDEE estimate

    return {
        bmi: bmi.toFixed(1),
        bodyFat: bf > 0 ? bf.toFixed(1) : '—',
        proteinGoal: proteinTarget,
        kcalGoal: kcalTarget
    };
}

// ── Food Items ───────────────────────────────────────────────
async function searchFoods(query = '') {
    let q = _sb.from('food_items').select('*').order('name');
    if (query.trim()) {
        const keywords = query.trim().split(/\s+/);
        keywords.forEach(word => {
            q = q.ilike('name', `%${word}%`);
        });
    }
    return q.limit(30);
}

async function addCustomFood(userId, food) {
    return _sb.from('food_items').insert({ ...food, is_custom: true, created_by: userId }).select().single();
}

// ── Meal Logs ────────────────────────────────────────────────
async function logMeal({ userId, mealType, mealName, portionSize, logDate, items }) {
    // 1. Insert meal log
    const { data: meal, error: mealErr } = await _sb
        .from('meal_logs')
        .insert({ user_id: userId, meal_type: mealType, meal_name: mealName, portion_size: portionSize, log_date: logDate })
        .select().single();
    if (mealErr) return { error: mealErr };

    // 2. Insert food items
    if (items && items.length > 0) {
        const rows = items.map(item => ({
            meal_log_id: meal.id,
            food_item_id: item.id || null,
            food_name: item.name,
            quantity: item.quantity || 1,
            kcal: item.kcal || 0,
            protein_g: item.protein_g || 0,
            carbs_g: item.carbs_g || 0,
            fats_g: item.fats_g || 0,
        }));
        const { error: itemErr } = await _sb.from('meal_food_items').insert(rows);
        if (itemErr) return { error: itemErr };
    }
    return { data: meal };
}

async function getDailySummary(userId, date) {
    return _sb
        .from('daily_summary')
        .select('*')
        .eq('user_id', userId)
        .eq('log_date', date);
}

async function deleteMeal(mealLogId) {
    return _sb.from('meal_logs').delete().eq('id', mealLogId);
}

// ── Checklist ────────────────────────────────────────────────
async function getChecklist(userId, date) {
    if (!_sb) return { error: { message: 'Supabase client not initialized.' } };
    const { data, error } = await _sb
        .from('daily_checklists')
        .select('*')
        .eq('user_id', userId)
        .eq('log_date', date)
        .maybeSingle();

    if (error) return { error };

    // If doesn't exist, create it
    if (!data) {
        const { data: newRow, error: insErr } = await _sb
            .from('daily_checklists')
            .insert({ user_id: userId, log_date: date })
            .select().single();
        return { data: newRow, error: insErr };
    }
    return { data, error: null };
}

async function updateChecklist(userId, date, updates) {
    if (!_sb) return { error: { message: 'Supabase client not initialized.' } };
    return _sb
        .from('daily_checklists')
        .update(updates)
        .eq('user_id', userId)
        .eq('log_date', date);
}

async function getWeeklyChecklist(userId, dates) {
    if (!_sb) return { error: null, data: [] };
    return _sb
        .from('daily_checklists')
        .select('*')
        .eq('user_id', userId)
        .in('log_date', dates);
}

// ── Date helpers ─────────────────────────────────────────────
function todayISO() {
    return new Date().toISOString().split('T')[0];
}

function formatDisplayDate() {
    const d = new Date();
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return days[d.getDay()].toUpperCase() + ', ' + months[d.getMonth()].toUpperCase() + ' ' + d.getDate();
}

// ── UI helpers ───────────────────────────────────────────────
function showToast(msg, type = 'success') {
    let toast = document.getElementById('_toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = '_toast';
        toast.style.cssText = `
      position:fixed;bottom:90px;left:50%;transform:translateX(-50%) translateY(20px);
      padding:10px 20px;border-radius:50px;font-size:13px;font-weight:600;
      color:#fff;z-index:9999;opacity:0;transition:all 0.3s;pointer-events:none;
      font-family:'Inter',sans-serif;max-width:300px;text-align:center;
    `;
        document.body.appendChild(toast);
    }
    toast.textContent = msg;
    toast.style.background = type === 'error' ? '#ef4444' : '#10b981';
    requestAnimationFrame(() => {
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(-50%) translateY(0)';
    });
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(-50%) translateY(20px)';
    }, 2800);
}

function showLoading(show, btnEl) {
    if (!btnEl) return;
    btnEl.disabled = show;
    btnEl.dataset.originalText = btnEl.dataset.originalText || btnEl.textContent;
    btnEl.textContent = show ? '⏳ Please wait...' : btnEl.dataset.originalText;
}
