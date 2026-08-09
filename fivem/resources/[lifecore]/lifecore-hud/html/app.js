const $ = (id) => document.getElementById(id);

const hud = $('hud');
const toasts = $('toasts');

function formatMoney(amount) {
    return '$' + Math.floor(amount).toLocaleString('en-US');
}

// Briefly highlight a money value when it changes.
const lastMoney = { cash: null, bank: null };
function setMoney(id, value) {
    const el = $(id);
    el.textContent = formatMoney(value);
    if (lastMoney[id] !== null && lastMoney[id] !== value) {
        el.classList.add('bump');
        setTimeout(() => el.classList.remove('bump'), 600);
    }
    lastMoney[id] = value;
}

function setBar(name, percent) {
    percent = Math.max(0, Math.min(100, percent));
    $('bar-' + name).style.width = percent + '%';
    const stat = $('stat-' + name);
    stat.classList.toggle('low', percent > 0 && percent <= 15);
    if (name === 'armor') stat.classList.toggle('empty', percent <= 0);
}

function notify(message, level) {
    const toast = document.createElement('div');
    toast.className = 'toast ' + (level || 'info');
    toast.textContent = message;
    toasts.appendChild(toast);
    setTimeout(() => {
        toast.classList.add('leaving');
        setTimeout(() => toast.remove(), 350);
    }, 4500);
    // Keep the stack bounded even under notification spam.
    while (toasts.children.length > 6) toasts.firstChild.remove();
}

window.addEventListener('message', ({ data }) => {
    switch (data.action) {
        case 'visible':
            hud.classList.toggle('hidden', !data.visible);
            break;
        case 'state':
            setMoney('cash', data.money?.cash ?? 0);
            setMoney('bank', data.money?.bank ?? 0);
            setBar('hunger', data.hunger);
            setBar('thirst', data.thirst);
            if (data.job) {
                $('job').textContent = data.job.name === 'unemployed'
                    ? ''
                    : `${data.job.label} · ${data.job.gradeLabel}`;
            }
            break;
        case 'vitals':
            setBar('health', data.health);
            setBar('armor', data.armor);
            break;
        case 'notify':
            notify(data.message, data.level);
            break;
    }
});
