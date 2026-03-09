/* ── chilllixhub-inject | html/script.js ──────────────────────────────────
 * NUI logic: communicates with the FiveM client-side Lua resource via:
 *   NUI → Lua  :  fetch('https://chilllixhub-inject/<callback>', ...)
 *   Lua → NUI  :  window.addEventListener('message', ...)
 * ───────────────────────────────────────────────────────────────────────── */

'use strict';

// ── DOM refs ──────────────────────────────────────────────────────────────
const app              = document.getElementById('app');
const codeInput        = document.getElementById('code-input');
const playerIdInput    = document.getElementById('player-id');
const charCounter      = document.getElementById('char-counter');
const outputLog        = document.getElementById('output-log');
const historyList      = document.getElementById('history-list');
const btnExecute       = document.getElementById('btn-execute');
const btnClose         = document.getElementById('btn-close');
const btnClearCode     = document.getElementById('btn-clear-code');
const btnClearOutput   = document.getElementById('btn-clear-output');
const btnRefreshHistory= document.getElementById('btn-refresh-history');
const targetGroup      = document.getElementById('target-group');

// Monitor DOM refs
const tabNav            = document.getElementById('tab-nav');
const monitorFeed       = document.getElementById('monitor-feed');
const monitorDot        = document.getElementById('monitor-dot');
const monitorStatusLabel= document.getElementById('monitor-status-label');
const monitorCount      = document.getElementById('monitor-count');
const btnMonitorToggle  = document.getElementById('btn-monitor-toggle');
const btnMonitorClear   = document.getElementById('btn-monitor-clear');
const monitorFilter     = document.getElementById('monitor-filter');
const monitorAutoscroll = document.getElementById('monitor-autoscroll');

// ── State ─────────────────────────────────────────────────────────────────
let currentTarget   = 'local';
let maxCodeLength   = 8192;   // updated if Lua sends the configured limit
let currentTab      = 'injector';
let monitorActive   = false;
let monitorTotal    = 0;      // total captured entries (including filtered-out)

// ── Tab switching ─────────────────────────────────────────────────────────

/** Programmatically activate a tab by name, reloading monitor entries if needed. */
function switchTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(b => {
        b.classList.toggle('active', b.dataset.tab === tab);
    });
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.add('hidden'));
    const panel = document.getElementById('tab-' + tab);
    if (panel) panel.classList.remove('hidden');
    currentTab = tab;
    if (tab === 'monitor') refreshMonitorEntries();
}

tabNav.addEventListener('click', (e) => {
    const btn = e.target.closest('.tab-btn');
    if (!btn) return;
    const tab = btn.dataset.tab;
    if (tab === currentTab) return;
    switchTab(tab);
});

// ── Target selection ──────────────────────────────────────────────────────
targetGroup.addEventListener('click', (e) => {
    const btn = e.target.closest('.target-btn');
    if (!btn) return;

    document.querySelectorAll('.target-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentTarget = btn.dataset.target;

    // Show player-id input only for 'client' target.
    playerIdInput.classList.toggle('hidden', currentTarget !== 'client');
});

// ── Character counter ─────────────────────────────────────────────────────
codeInput.addEventListener('input', updateCounter);

function updateCounter() {
    const len = codeInput.value.length;
    charCounter.textContent = `${len} / ${maxCodeLength}`;
    charCounter.classList.remove('warn', 'limit');
    if (len > maxCodeLength) {
        charCounter.classList.add('limit');
    } else if (len > maxCodeLength * 0.9) {
        charCounter.classList.add('warn');
    }
}

// ── Tab key support in textarea ───────────────────────────────────────────
codeInput.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
        e.preventDefault();
        const start = codeInput.selectionStart;
        const end   = codeInput.selectionEnd;
        codeInput.value = codeInput.value.substring(0, start) + '    ' + codeInput.value.substring(end);
        codeInput.selectionStart = codeInput.selectionEnd = start + 4;
        updateCounter();
    }

    // Ctrl+Enter → execute
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        execute();
    }
});

// ── Execute ───────────────────────────────────────────────────────────────
btnExecute.addEventListener('click', execute);

function execute() {
    const code = codeInput.value.trim();
    if (!code) {
        addOutput('info', 'No code to execute.');
        return;
    }
    if (code.length > maxCodeLength) {
        addOutput('fail', `Code is too long (${code.length} / ${maxCodeLength} chars).`);
        return;
    }

    const payload = { type: currentTarget, code };
    if (currentTarget === 'client') {
        const pid = parseInt(playerIdInput.value, 10);
        if (isNaN(pid) || pid < 1) {
            addOutput('fail', 'Enter a valid Player ID for the "Client" target.');
            playerIdInput.focus();
            return;
        }
        payload.targetId = pid;
    }

    btnExecute.disabled = true;

    nuiPost('execute', payload)
        .then(resp => {
            if (resp && resp.ok) {
                addOutput('ok',   resp.msg || 'Executed.', resp.id);
            } else {
                addOutput('fail', resp && resp.msg ? resp.msg : 'Execution failed.');
            }
        })
        .catch(() => addOutput('fail', 'NUI callback error.'))
        .finally(() => { btnExecute.disabled = false; });
}

// ── Close ─────────────────────────────────────────────────────────────────
btnClose.addEventListener('click', closeUI);

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeUI();
});

function closeUI() {
    nuiPost('close', {}).catch(() => {});
    hide();
}

// ── Clear buttons ─────────────────────────────────────────────────────────
btnClearCode.addEventListener('click', () => {
    codeInput.value = '';
    updateCounter();
    codeInput.focus();
});

btnClearOutput.addEventListener('click', () => {
    outputLog.innerHTML = '<div class="output-placeholder">Results will appear here…</div>';
});

// ── History ───────────────────────────────────────────────────────────────
btnRefreshHistory.addEventListener('click', refreshHistory);

function refreshHistory() {
    nuiPost('getHistory', {})
        .then(resp => {
            if (resp && Array.isArray(resp.history)) {
                renderHistory(resp.history);
            }
        })
        .catch(() => {});
}

function renderHistory(records) {
    if (!records || records.length === 0) {
        historyList.innerHTML = '<div class="history-placeholder">No injections yet.</div>';
        return;
    }

    historyList.innerHTML = '';
    // Most-recent first.
    const sorted = [...records].reverse();
    sorted.forEach(r => {
        const item = document.createElement('div');
        item.className = 'history-item';
        item.title = r.code || '';

        const preview = (r.code || '').replace(/\n/g, ' ').substring(0, 55);
        const ellipsis = (r.code || '').length > 55 ? '…' : '';

        item.innerHTML = `
            <div class="h-meta">
                <span class="h-id">#${r.id}</span>
                <span class="h-type ${r.type}">${r.type}</span>
                <span class="h-time">${r.time || ''}</span>
            </div>
            <div class="h-preview">${escapeHtml(preview)}${ellipsis}</div>
        `;

        // Click → load code back into editor.
        item.addEventListener('click', () => {
            codeInput.value = r.code || '';
            updateCounter();
            codeInput.focus();
        });

        historyList.appendChild(item);
    });
}

// ── Trigger Monitor ───────────────────────────────────────────────────────

// Debounce auto-scroll so rapid event bursts only trigger one reflow per frame.
let _scrollPending = false;
function scheduleMonitorScroll() {
    if (_scrollPending) return;
    _scrollPending = true;
    requestAnimationFrame(() => {
        monitorFeed.scrollTop = monitorFeed.scrollHeight;
        _scrollPending = false;
    });
}

btnMonitorToggle.addEventListener('click', () => {
    if (monitorActive) {
        stopMonitor();
    } else {
        startMonitor();
    }
});

btnMonitorClear.addEventListener('click', () => {
    nuiPost('clearMonitor', {}).catch(() => {});
    const ph = document.createElement('div');
    ph.className = 'monitor-placeholder';
    ph.textContent = 'Log cleared. Monitor is ' + (monitorActive ? 'still running…' : 'idle.');
    monitorFeed.innerHTML = '';
    monitorFeed.appendChild(ph);
    monitorTotal = 0;
    updateMonitorCount();
});

monitorFilter.addEventListener('input', applyMonitorFilter);

function startMonitor() {
    nuiPost('startMonitor', {})
        .then(() => {
            monitorActive = true;
            setMonitorUI(true);
            // Close the NUI so monitoring runs in the background of the game.
            nuiPost('close', {}).catch(() => {});
            hide();
        })
        .catch(() => {});
}

function stopMonitor() {
    nuiPost('stopMonitor', {})
        .then(() => {
            monitorActive = false;
            setMonitorUI(false);
        })
        .catch(() => {});
}

function setMonitorUI(active) {
    monitorDot.className         = 'monitor-dot ' + (active ? 'active' : 'idle');
    monitorStatusLabel.textContent = active ? 'Monitoring…' : 'Idle';
    monitorStatusLabel.className = 'monitor-status-label' + (active ? ' active' : '');
    btnMonitorToggle.textContent  = active ? '■ Stop' : '▶ Start';
    btnMonitorToggle.className    = 'monitor-toggle-btn ' + (active ? 'stop' : 'start');
}

/**
 * Clear the monitor feed and reload all accumulated entries from Lua.
 */
function refreshMonitorEntries() {
    nuiPost('getMonitorEntries', {})
        .then(resp => {
            if (resp && Array.isArray(resp.entries)) {
                monitorFeed.innerHTML = '';
                monitorTotal = 0;
                resp.entries.forEach(addMonitorEntry);
            }
        })
        .catch(() => {});
}

/**
 * Map a direction string to a CSS class for colour-coding.
 * Direction strings come from Lua:
 *   '→ server'      – TriggerServerEvent (outgoing)
 *   '→ srv·latent'  – TriggerLatentServerEvent
 *   '↔ local'       – TriggerEvent (local)
 *   '← srv·recv'    – event received/relayed by the server-side raw handler
 *   '← client·recv' – event received by client-side raw handler (TriggerClientEvent)
 * @param {string} dir
 * @returns {string}
 */
function dirClass(dir) {
    if (!dir) return 'local';
    const d = dir.toLowerCase();
    if (d.includes('latent'))  return 'to-latent';
    if (d.includes('server'))  return 'to-server';
    // '← srv·recv' and '← client·recv' and any other incoming/receive variants
    if (d.includes('recv'))    return 'from-server';
    return 'local';
}

/**
 * Append one monitor entry element to the feed.
 * @param {object} entry  { time, dir, event, args, src }
 */
function addMonitorEntry(entry) {
    if (!entry || !entry.event) return;

    // Remove placeholder if present.
    const ph = monitorFeed.querySelector('.monitor-placeholder');
    if (ph) ph.remove();

    monitorTotal += 1;
    updateMonitorCount();

    const row = document.createElement('div');
    row.className    = 'monitor-entry';
    row.dataset.event = (entry.event || '').toLowerCase();

    const argsText = entry.args  ? escapeHtml(entry.args)  : '';
    const srcText  = entry.src   ? escapeHtml(entry.src)   : '';

    row.innerHTML = `
        <span class="me-time">${escapeHtml(entry.time || '')}</span>
        <span class="me-dir ${dirClass(entry.dir)}">${escapeHtml(entry.dir || '')}</span>
        <div class="me-body">
            <span class="me-event">${escapeHtml(entry.event || '')}</span>
            ${argsText ? `<span class="me-args">${argsText}</span>` : ''}
            ${srcText  ? `<span class="me-src">src: ${srcText}</span>` : ''}
        </div>
    `;

    // Apply current filter immediately.
    const filter = monitorFilter.value.trim().toLowerCase();
    if (filter && !row.dataset.event.includes(filter)) {
        row.classList.add('hidden');
    }

    monitorFeed.appendChild(row);

    if (monitorAutoscroll.checked && !row.classList.contains('hidden')) {
        scheduleMonitorScroll();
    }
}

function applyMonitorFilter() {
    const filter = monitorFilter.value.trim().toLowerCase();
    monitorFeed.querySelectorAll('.monitor-entry').forEach(row => {
        const name = row.dataset.event || '';
        row.classList.toggle('hidden', !!(filter && !name.includes(filter)));
    });
}

function updateMonitorCount() {
    monitorCount.textContent = `${monitorTotal} event${monitorTotal !== 1 ? 's' : ''} captured`;
}

// ── Lua → NUI messages ────────────────────────────────────────────────────
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        case 'setVisible':
            if (data.visible) {
                // Sync monitor active state from Lua (authoritative source).
                // This keeps the JS flag in sync even after a resource restart
                // where Lua resets to false but the NUI page was not reloaded.
                if (typeof data.monitorActive === 'boolean') {
                    monitorActive = data.monitorActive;
                    setMonitorUI(monitorActive);
                }
                show();
                if (data.maxCodeLength) {
                    maxCodeLength = data.maxCodeLength;
                    updateCounter();
                }
                refreshHistory();
                // If monitoring is running in the background, switch directly to
                // the Monitor tab so the user can see accumulated entries.
                if (monitorActive) {
                    switchTab('monitor');
                }
            } else {
                hide();
            }
            break;

        case 'addResult':
            addOutput(
                data.ok ? 'ok' : 'fail',
                data.msg || (data.ok ? 'OK' : 'Failed'),
                data.id
            );
            break;

        case 'updateHistory':
            if (Array.isArray(data.history)) {
                renderHistory(data.history);
            }
            break;

        case 'monitorEntry':
            addMonitorEntry(data.entry);
            break;
    }
});

// ── Helpers ───────────────────────────────────────────────────────────────
function show() {
    app.classList.remove('hidden');
    codeInput.focus();
}

function hide() {
    app.classList.add('hidden');
}

function addOutput(type, msg, id) {
    // Remove placeholder if present.
    const placeholder = outputLog.querySelector('.output-placeholder');
    if (placeholder) placeholder.remove();

    const entry = document.createElement('div');
    entry.className = 'output-entry';

    const idRef = id != null ? ` <span class="id-ref">[#${id}]</span>` : '';
    entry.innerHTML = `
        <span class="tag ${type}">${type.toUpperCase()}</span>
        <span class="msg">${escapeHtml(msg)}${idRef}</span>
    `;
    outputLog.appendChild(entry);
    outputLog.scrollTop = outputLog.scrollHeight;
}

function escapeHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

/**
 * Post a NUI callback to the Lua resource.
 * @param {string} name  Callback name registered with RegisterNUICallback.
 * @param {object} body  JSON-serialisable payload.
 * @returns {Promise<object>} Resolved with the JSON response from Lua.
 */
function nuiPost(name, body) {
    return fetch(`https://chilllixhub-inject/${name}`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(body),
    }).then(r => r.json());
}
