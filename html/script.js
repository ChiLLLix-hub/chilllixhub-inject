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

// ── State ─────────────────────────────────────────────────────────────────
let currentTarget  = 'local';
let maxCodeLength  = 8192;   // updated if Lua sends the configured limit

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

// ── Lua → NUI messages ────────────────────────────────────────────────────
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        case 'setVisible':
            if (data.visible) {
                show();
                if (data.maxCodeLength) {
                    maxCodeLength = data.maxCodeLength;
                    updateCounter();
                }
                refreshHistory();
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
