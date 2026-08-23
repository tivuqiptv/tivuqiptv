const $ = (selector) => document.querySelector(selector);
const state = {
  devices: [],
  payments: [],
  privacyRequests: [],
  auditEvents: [],
  user: null,
  currentFilter: 'all',
};

async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: 'same-origin',
    headers: { 'content-type': 'application/json', ...(options.headers ?? {}) },
    ...options,
  });
  const payload = await response.json().catch(() => ({}));
  if (response.status === 401) {
    const isLoginRequest = path === '/v1/admin/session' && options.method === 'POST';
    if (!isLoginRequest) showLogin();
    throw new Error(payload.error ?? 'Oturum sona erdi.');
  }
  if (!response.ok) throw new Error(payload.error ?? `Sunucu hatası (${response.status})`);
  return payload;
}

function showLogin() {
  $('#dashboard-view').hidden = true;
  $('#login-view').hidden = false;
  $('#login-password').value = '';
}

function showDashboard(user) {
  state.user = user;
  $('#admin-email').textContent = user.displayName || user.email;
  $('#login-view').hidden = true;
  $('#dashboard-view').hidden = false;
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[character]);
}

function formatDate(value) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('tr-TR', {
    dateStyle: 'medium', timeStyle: 'short',
  }).format(new Date(value));
}

function formatMoney(amountMinor, currency) {
  if (!Number.isInteger(amountMinor) || !currency) return '—';
  return new Intl.NumberFormat('tr-TR', {
    style: 'currency', currency: String(currency).toUpperCase(),
  }).format(amountMinor / 100);
}

function statusInfo(device) {
  if (device.license_status === 'active') return ['Aktif', 'active'];
  if (device.license_status) return [device.license_status, 'inactive'];
  return ['Lisanssız', 'none'];
}

function formatTrial(device) {
  if (device.license_status === 'active') {
    return `<div class="trial-cell">
      <span class="trial-tag trial-lifetime">Ömür Boyu</span>
    </div>`;
  }
  if (!device.trial_started_at) {
    return `<span class="muted">—</span>`;
  }
  const startDate = new Intl.DateTimeFormat('tr-TR', {
    day: '2-digit', month: '2-digit', year: 'numeric'
  }).format(new Date(device.trial_started_at));

  if (!device.trial_expires_at) {
    return `<span class="trial-date">${escapeHtml(startDate)}</span>`;
  }

  const now = Date.now();
  const expire = new Date(device.trial_expires_at).getTime();
  const diffMs = expire - now;
  const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

  let daysText = '';
  let tagClass = 'trial-active';
  if (diffDays > 0) {
    daysText = `(${diffDays} gün kaldı)`;
    tagClass = diffDays <= 3 ? 'trial-expiring' : 'trial-active';
  } else if (diffDays === 0) {
    daysText = `(Bugün bitiyor)`;
    tagClass = 'trial-expiring';
  } else {
    daysText = `(Süresi doldu)`;
    tagClass = 'trial-expired';
  }

  return `<div class="trial-cell">
    <span class="trial-date">${escapeHtml(startDate)}</span>
    <span class="trial-tag ${tagClass}">${escapeHtml(daysText)}</span>
  </div>`;
}

function renderDevices() {
  const query = $('#device-search').value.trim().toLocaleLowerCase('tr-TR');
  const now = Date.now();
  const oneDayAgo = now - 24 * 3600 * 1000;

  // 1. Text search filter
  let devices = state.devices.filter((device) => [
    device.device_code, device.model, device.customer_email,
  ].some((value) => String(value ?? '').toLocaleLowerCase('tr-TR').includes(query)));

  // 2. Metric card filter
  if (state.currentFilter === 'trial') {
    devices = devices.filter((device) => {
      if (device.license_status === 'active') return false;
      const expire = device.trial_expires_at ? new Date(device.trial_expires_at).getTime() : 0;
      return expire > now;
    });
  } else if (state.currentFilter === 'active') {
    devices = devices.filter((device) => device.license_status === 'active');
  } else if (state.currentFilter === 'inactive') {
    devices = devices.filter((device) => {
      if (device.license_status === 'active') return false;
      const expire = device.trial_expires_at ? new Date(device.trial_expires_at).getTime() : 0;
      return (expire > 0 && expire <= now) || (device.license_status && device.license_status !== 'active');
    });
  } else if (state.currentFilter === 'recent') {
    devices = devices.filter((device) => {
      const seen = device.last_seen_at ? new Date(device.last_seen_at).getTime() : 0;
      return seen >= oneDayAgo;
    });
  }

  // 3. Sorting: "siralama kalan gune gore siralanmali en erken biten en ustte olmali."
  devices.sort((a, b) => {
    function getSortKey(d) {
      if (d.license_status === 'active') return [3, 0];
      const expire = d.trial_expires_at ? new Date(d.trial_expires_at).getTime() : 0;
      if (expire > 0) {
        if (expire >= now) {
          return [1, expire]; // Active trials: earliest expiring first
        }
        return [0, expire]; // Expired trials
      }
      return [2, -(d.last_seen_at ? new Date(d.last_seen_at).getTime() : 0)];
    }

    const [priA, valA] = getSortKey(a);
    const [priB, valB] = getSortKey(b);
    if (priA !== priB) return priA - priB;
    return valA - valB;
  });

  $('#empty-state').hidden = devices.length !== 0;
  $('#device-rows').innerHTML = devices.map((device) => {
    const [label, className] = statusInfo(device);
    const active = device.license_status === 'active';
    return `<tr>
      <td><span class="device-code">${escapeHtml(device.device_code)}</span>
        <span class="subline">${escapeHtml(device.model || device.platform || 'Android TV')}</span></td>
      <td>${escapeHtml(device.customer_email || '—')}</td>
      <td>${formatTrial(device)}</td>
      <td>${escapeHtml(formatDate(device.last_seen_at))}</td>
      <td><span class="badge ${className}">${escapeHtml(label)}</span></td>
      <td><button class="row-action ${active ? 'danger' : ''}" data-action="${active ? 'revoke' : 'activate'}"
        data-device="${escapeHtml(device.device_code)}" data-license="${escapeHtml(device.license_id || '')}">
        ${active ? 'İptal et' : 'Lisans aç'}</button></td>
    </tr>`;
  }).join('');
}

function renderPayments() {
  $('#payments-empty').hidden = state.payments.length !== 0;
  $('#payment-rows').innerHTML = state.payments.map((payment) => `<tr>
    <td>${escapeHtml(formatDate(payment.created_at))}</td>
    <td>${escapeHtml(payment.provider)}</td>
    <td><span class="device-code">${escapeHtml(payment.device_code || '—')}</span></td>
    <td>${escapeHtml(payment.customer_email || '—')}</td>
    <td>${escapeHtml(formatMoney(payment.amount_minor, payment.currency))}</td>
    <td><span class="badge ${payment.status === 'paid' ? 'active' : 'inactive'}">${escapeHtml(payment.status)}</span></td>
  </tr>`).join('');
}

function renderAuditEvents() {
  $('#audit-empty').hidden = state.auditEvents.length !== 0;
  $('#audit-rows').innerHTML = state.auditEvents.map((event) => `<tr>
    <td>${escapeHtml(formatDate(event.created_at))}</td>
    <td>${escapeHtml(event.action)}</td>
    <td>${escapeHtml(event.actor_id || event.actor_type)}</td>
    <td>${escapeHtml([event.target_type, event.target_id].filter(Boolean).join(': ') || '—')}</td>
    <td>${escapeHtml(event.ip_address || '—')}</td>
  </tr>`).join('');
}

function renderPrivacyRequests() {
  $('#privacy-empty').hidden = state.privacyRequests.length !== 0;
  $('#privacy-rows').innerHTML = state.privacyRequests.map((request) => {
    const pending = request.status === 'pending';
    return `<tr>
      <td>${escapeHtml(formatDate(request.requested_at))}</td>
      <td><span class="device-code">${escapeHtml(request.device_code || 'Anonimleştirildi')}</span>
        <span class="subline">${escapeHtml(request.model || '—')}</span></td>
      <td>${escapeHtml(request.customer_email || '—')}</td>
      <td>${escapeHtml(request.license_status || 'Lisans yok')}</td>
      <td><span class="badge ${pending ? 'inactive' : 'none'}">${escapeHtml(request.status)}</span></td>
      <td>${pending ? `<button class="row-action danger" data-privacy-complete="${escapeHtml(request.id)}" data-device="${escapeHtml(request.device_code || '')}">Silme işlemini tamamla</button>` : ''}</td>
    </tr>`;
  }).join('');
}

async function switchView(name) {
  document.querySelectorAll('.view-content').forEach((element) => { element.hidden = true; });
  document.querySelectorAll('[data-view]').forEach((button) => {
    button.classList.toggle('active', button.dataset.view === name);
  });
  $(`#${name}-content`).hidden = false;
  try {
    if (name === 'payments') {
      state.payments = (await api('/v1/admin/payments')).payments;
      renderPayments();
    } else if (name === 'privacy') {
      state.privacyRequests = (await api('/v1/admin/privacy/deletion-requests')).requests;
      renderPrivacyRequests();
    } else if (name === 'audit') {
      state.auditEvents = (await api('/v1/admin/audit-events')).events;
      renderAuditEvents();
    }
  } catch (error) { message(error.message, true); }
}

function message(text, error = false) {
  const element = $('#panel-message');
  element.hidden = false;
  element.textContent = text;
  element.style.color = error ? 'var(--red)' : '';
  window.setTimeout(() => { element.hidden = true; }, 4500);
}

async function loadDashboard() {
  $('#refresh-button').disabled = true;
  try {
    const [dashboard, devices] = await Promise.all([
      api('/v1/admin/dashboard'), api('/v1/admin/devices'),
    ]);
    $('#total-devices').textContent = dashboard.summary.total_devices ?? '0';
    $('#trial-devices').textContent = dashboard.summary.trial_devices ?? '0';
    $('#active-licenses').textContent = dashboard.summary.active_licenses ?? '0';
    $('#inactive-licenses').textContent = dashboard.summary.inactive_licenses ?? '0';
    $('#recent-devices').textContent = dashboard.summary.devices_last_24h ?? '0';
    state.devices = devices.devices;
    renderDevices();
  } catch (error) {
    message(error.message, true);
  } finally {
    $('#refresh-button').disabled = false;
  }
}

$('#login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  $('#login-error').textContent = '';
  try {
    const result = await api('/v1/admin/session', {
      method: 'POST',
      body: JSON.stringify({
        email: $('#login-email').value,
        password: $('#login-password').value,
      }),
    });
    showDashboard(result.user);
    await loadDashboard();
  } catch (error) {
    $('#login-error').textContent = error.message === 'invalid_credentials'
      ? 'E-posta veya parola yanlış.' : error.message;
  }
});

$('#privacy-rows').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-privacy-complete]');
  if (!button) return;
  const warning = `${button.dataset.device} cihazının sunucu kimliği anonimleştirilecek ve bu cihaz lisansını kaybedecek. Bu işlem geri alınamaz. Devam edilsin mi?`;
  if (!window.confirm(warning)) return;
  try {
    await api(`/v1/admin/privacy/deletion-requests/${button.dataset.privacyComplete}/complete`, {
      method: 'POST',
      body: JSON.stringify({ notes: 'Yönetim panelinden tamamlandı.' }),
    });
    message('Veri silme talebi tamamlandı.');
    state.privacyRequests = (await api('/v1/admin/privacy/deletion-requests')).requests;
    renderPrivacyRequests();
    await loadDashboard();
  } catch (error) { message(error.message, true); }
});

$('#logout-button').addEventListener('click', async () => {
  await api('/v1/admin/session', { method: 'DELETE' }).catch(() => {});
  showLogin();
});
$('#refresh-button').addEventListener('click', loadDashboard);
$('#device-search').addEventListener('input', renderDevices);
document.querySelectorAll('[data-view]').forEach((button) => {
  button.addEventListener('click', () => switchView(button.dataset.view));
});
$('#activate-cancel').addEventListener('click', () => $('#activate-dialog').close());

document.querySelectorAll('.metric-card').forEach((card) => {
  card.addEventListener('click', () => {
    document.querySelectorAll('.metric-card').forEach((c) => c.classList.remove('active'));
    card.classList.add('active');
    state.currentFilter = card.dataset.filter || 'all';
    renderDevices();
  });
});

$('#device-rows').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-action]');
  if (!button) return;
  if (button.dataset.action === 'activate') {
    $('#activate-device-code').value = button.dataset.device;
    $('#activate-title').textContent = `${button.dataset.device} için lisans aç`;
    $('#customer-email').value = '';
    $('#customer-name').value = '';
    $('#activate-dialog').showModal();
    return;
  }
  if (button.dataset.action === 'revoke') {
    if (!window.confirm(`${button.dataset.device} cihazının lisansı iptal edilsin mi?`)) return;
    try {
      await api(`/v1/admin/licenses/${button.dataset.license}/revoke`, {
        method: 'POST',
        body: JSON.stringify({ reason: 'Yönetici tarafından iptal edildi.' }),
      });
      message('Lisans iptal edildi.');
      await loadDashboard();
    } catch (error) { message(error.message, true); }
  }
});

$('#activate-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const deviceCode = $('#activate-device-code').value;
  try {
    await api('/v1/admin/licenses', {
      method: 'POST',
      body: JSON.stringify({
        deviceCode,
        customerEmail: $('#customer-email').value || null,
        customerName: $('#customer-name').value || null,
        kind: 'lifetime',
      }),
    });
    $('#activate-dialog').close();
    message(`${deviceCode} için ömür boyu lisans açıldı.`);
    await loadDashboard();
  } catch (error) {
    message(error.message, true);
  }
});

api('/v1/admin/session').then((result) => {
  showDashboard(result.user);
  return loadDashboard();
}).catch(() => showLogin());
