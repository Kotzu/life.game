/* Trophy Room NUI — dependency-free. All user-facing strings arrive from the
   Lua locale packs (data.strings) with English fallbacks kept here. */
'use strict';

const root = document.getElementById('root');
const screenEl = document.getElementById('screen');
const titleEl = document.getElementById('title');

const RESOURCE = (window.GetParentResourceName && window.GetParentResourceName()) || 'kotzu_trophy_room';

let STR = {};
function T(key, fallback) {
  return STR[key] || fallback;
}

function nui(name, data) {
  return fetch(`https://${RESOURCE}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

function close() {
  root.classList.add('hidden');
  nui('ktr:close');
}
document.getElementById('closeBtn').addEventListener('click', close);
window.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });

function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') node.className = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children) {
    node.append(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return node;
}

function chipRow(items, selectedId, onPick) {
  const row = el('div', { class: 'row' });
  for (const item of items) {
    const b = el('button', {
      class: item.id === selectedId ? 'selected' : '',
      onclick: () => {
        row.querySelectorAll('button').forEach((x) => x.classList.remove('selected'));
        b.classList.add('selected');
        onPick(item.id);
      },
    }, item.label);
    row.append(b);
  }
  return row;
}

/* ------------------------------------------------------------------ wizard */

function renderWizard(data) {
  titleEl.textContent = T('newDisplay', 'New Display');
  const state = {
    type: 'mannequin',
    gender: data.playerGender || 'male',
    outfitSource: 'current',
    savedId: null,
    poseId: (data.poses[0] || {}).id || 'neutral',
    platform: 'none',
    weaponKind: 'stand',
    caseStyle: data.defaultCaseStyle || 'vertical',
    itemName: '',
    label: '',
  };

  const body = el('div', {});

  body.append(el('div', { class: 'section-label' }, T('displayType', 'Display type')));
  const types = [
    { id: 'mannequin', label: T('mannequin', 'Mannequin') },
    { id: 'weapon', label: T('weapon', 'Weapon') },
  ];
  body.append(chipRow(types, state.type, (id) => { state.type = id; renderTypeSection(); }));

  const typeSection = el('div', {});
  body.append(typeSection);

  function renderTypeSection() {
    typeSection.replaceChildren();
    if (state.type === 'mannequin') {
      if (!data.manifestBuilt) {
        typeSection.append(el('div', { class: 'warn' }, T('manifestWarn',
          'Mannequin assets are not built (manifest v0). Run the asset pipeline first — placement will be refused.')));
      }
      typeSection.append(el('div', { class: 'section-label' }, T('gender', 'Gender')));
      typeSection.append(chipRow(
        [{ id: 'male', label: T('male', 'Male') }, { id: 'female', label: T('female', 'Female') }],
        state.gender, (id) => { state.gender = id; }));

      typeSection.append(el('div', { class: 'section-label' }, T('outfit', 'Outfit')));
      const outfitOpts = [
        { id: 'current', label: T('myCurrentOutfit', 'My current outfit') },
        { id: 'none', label: T('bareMannequin', 'Bare mannequin') },
      ];
      if (Array.isArray(data.savedOutfits) && data.savedOutfits.length) {
        outfitOpts.push({ id: 'saved', label: T('savedOutfit', 'Saved outfit…') });
      }
      const savedRow = el('div', {});
      typeSection.append(chipRow(outfitOpts, state.outfitSource, (id) => {
        state.outfitSource = id;
        state.savedId = null;
        savedRow.replaceChildren();
        if (id === 'saved') {
          // concept-style SELECT OUTFIT panel: list + count + selected + footer
          const list = Array.isArray(data.savedOutfits) ? data.savedOutfits : [];
          const panel = el('div', { class: 'outfit-panel' });
          const head = el('div', { class: 'outfit-head' },
            el('span', {}, T('selectOutfit', 'SELECT OUTFIT')),
            el('span', { class: 'outfit-count' }, `0 / ${list.length}`));
          const listEl = el('div', { class: 'outfit-list' });
          const footer = el('div', { class: 'outfit-foot' }, T('noOutfitSelected', 'No outfit selected'));
          list.forEach((o, i) => {
            const row = el('div', {
              class: 'outfit-row',
              onclick: () => {
                state.savedId = String(o.id);
                listEl.querySelectorAll('.outfit-row').forEach((r) => r.classList.remove('selected'));
                row.classList.add('selected');
                head.querySelector('.outfit-count').textContent = `${i + 1} / ${list.length}`;
                footer.replaceChildren(
                  el('div', { class: 'outfit-foot-name' }, o.label),
                  el('div', { class: 'outfit-foot-sub' }, o.model || ''));
              },
            }, o.label);
            listEl.append(row);
          });
          panel.append(head, listEl, footer);
          savedRow.append(panel);
        }
      }));
      typeSection.append(savedRow);

      typeSection.append(el('div', { class: 'section-label' }, T('pose', 'Pose')));
      typeSection.append(chipRow(data.poses, state.poseId, (id) => { state.poseId = id; }));

      typeSection.append(el('div', { class: 'section-label' }, T('stand', 'Stand')));
      typeSection.append(chipRow(data.platforms, state.platform, (id) => { state.platform = id; }));
    } else {
      if (!data.inventoryFunctional) {
        typeSection.append(el('div', { class: 'warn' }, T('inventoryWarn',
          'No functional inventory bridge detected — weapon displays are disabled.')));
      }
      typeSection.append(el('div', { class: 'section-label' }, T('mount', 'Mount')));
      const caseRow = el('div', {});
      function renderCaseStyles() {
        caseRow.replaceChildren();
        if (state.weaponKind !== 'case') return;
        caseRow.append(el('div', { class: 'section-label' }, T('caseStyleLabel', 'Case shape')));
        const styles = (data.caseStyles || []).map((s) => ({
          id: s.id, label: T('case_' + s.id, s.id),
        }));
        caseRow.append(chipRow(styles, state.caseStyle, (id) => { state.caseStyle = id; }));
      }
      typeSection.append(chipRow([
        { id: 'wall', label: T('wallMount', 'Wall mount') },
        { id: 'stand', label: T('floorStand', 'Floor stand') },
        { id: 'case', label: T('glassCase', 'Glass case') },
      ], state.weaponKind, (id) => { state.weaponKind = id; renderCaseStyles(); }));
      typeSection.append(caseRow);
      renderCaseStyles();
      typeSection.append(el('div', { class: 'section-label' }, T('weaponItemName', 'Weapon item name')));
      typeSection.append(el('input', {
        type: 'text', placeholder: 'weapon_pistol',
        oninput: (e) => { state.itemName = e.target.value; },
      }));
      typeSection.append(el('div', { class: 'note' }, T('weaponNote',
        'The server verifies you own this exact weapon (by serial) and removes it from your inventory atomically. Retrieve it any time from the display.')));
    }
  }
  renderTypeSection();

  body.append(el('div', { class: 'section-label' }, T('labelOptional', 'Label (optional)')));
  body.append(el('input', {
    type: 'text', maxlength: '48', placeholder: T('labelPlaceholder', 'e.g. Patrol uniform 2024'),
    oninput: (e) => { state.label = e.target.value; },
  }));

  const placeBtn = el('button', {
    class: 'primary',
    onclick: () => {
      if (state.type === 'mannequin') {
        if (state.outfitSource === 'saved' && !state.savedId) {
          const panel = typeSection.querySelector('.outfit-panel');
          if (panel) { panel.classList.add('shake'); setTimeout(() => panel.classList.remove('shake'), 450); }
          return; // must pick a saved outfit first
        }
        nui('ktr:placeMannequin', {
          gender: state.gender,
          outfitSource: state.outfitSource === 'none' ? 'none' : (state.outfitSource === 'saved' ? 'saved' : 'current'),
          savedId: state.savedId,
          poseId: state.poseId,
          platform: state.platform,
          label: state.label,
        });
      } else {
        if (!data.inventoryFunctional || !state.itemName.trim()) return;
        nui('ktr:placeWeapon', {
          kind: state.weaponKind,
          caseStyle: state.caseStyle,
          itemName: state.itemName.trim(),
          label: state.label,
        });
      }
      root.classList.add('hidden');
    },
  }, T('startPlacement', 'Start placement'));
  body.append(placeBtn);
  body.append(el('div', { class: 'note' }, T('placementHint',
    'Placement: arrows move · Q/E rotate · PgUp/PgDn height · Shift fine · G ground · Tab snap · X collision · Enter confirm · Backspace cancel')));

  screenEl.replaceChildren(body);
}

/* ------------------------------------------------------------------ others */

function renderDetails(data) {
  titleEl.textContent = data.display.label || T('displayFallback', 'Display');
  const body = el('div', {});
  for (const line of data.lines || []) {
    body.append(el('div', { class: 'detail-line' }, line));
  }
  body.append(el('div', { class: 'section-label' }, T('rename', 'Rename')));
  const nameIn = el('input', { type: 'text', maxlength: '48', value: data.display.label || '' });
  const descIn = el('input', {
    type: 'text', maxlength: '256', value: data.display.description || '',
    placeholder: T('descriptionPlaceholder', 'Description'), style: 'margin-top:8px',
  });
  body.append(nameIn, descIn);
  body.append(el('button', {
    class: 'primary',
    onclick: () => {
      nui('ktr:rename', { uid: data.display.uid, label: nameIn.value, description: descIn.value });
      root.classList.add('hidden');
    },
  }, T('saveBtn', 'Save')));
  screenEl.replaceChildren(body);
}

function renderPoses(data) {
  titleEl.textContent = T('poseTitle', 'Pose');
  const body = el('div', {});
  for (const pose of data.poses) {
    body.append(el('button', {
      class: 'list' + (pose.id === data.current ? ' selected' : ''),
      onclick: () => {
        nui('ktr:setPose', { uid: data.uid, poseId: pose.id });
        root.classList.add('hidden');
      },
    }, pose.label));
  }
  screenEl.replaceChildren(body);
}

function renderConfirmRemove(data) {
  titleEl.textContent = T('removeTitle', 'Remove display');
  const body = el('div', {});
  const confirmTemplate = T('removeConfirm', 'Remove "%s"? This cannot be undone.');
  body.append(el('div', { class: 'detail-line' }, confirmTemplate.replace('%s', data.label)));
  body.append(el('button', {
    class: 'danger',
    onclick: () => {
      nui('ktr:confirmRemove', { uid: data.uid });
      root.classList.add('hidden');
    },
  }, T('removeBtn', 'Remove')));
  screenEl.replaceChildren(body);
}

function renderRotate(data) {
  titleEl.textContent = T('rotateTitle', 'Auto-rotate');
  const body = el('div', {});
  const state = { enabled: data.enabled === true, speed: data.speed || 12 };

  const toggle = el('button', {
    class: state.enabled ? 'selected' : '',
    onclick: () => {
      state.enabled = !state.enabled;
      toggle.classList.toggle('selected', state.enabled);
    },
  }, T('rotateEnable', 'Rotate the item slowly'));
  body.append(el('div', { class: 'row' }, toggle));

  body.append(el('div', { class: 'section-label' }, T('rotateSpeed', 'Rotation speed')));
  const readout = el('span', { class: 'slider-value' },
    `${state.speed} ${T('degPerSec', '°/s')}`);
  const slider = el('input', {
    type: 'range', min: String(data.minSpeed || 3), max: String(data.maxSpeed || 90),
    step: '1', value: String(state.speed),
    oninput: (e) => {
      state.speed = Number(e.target.value);
      readout.textContent = `${state.speed} ${T('degPerSec', '°/s')}`;
    },
  });
  body.append(el('div', { class: 'slider-row' }, slider, readout));

  body.append(el('button', {
    class: 'primary',
    onclick: () => {
      nui('ktr:setRotate', { uid: data.uid, enabled: state.enabled, speed: state.speed });
      root.classList.add('hidden');
    },
  }, T('saveBtn', 'Save')));
  screenEl.replaceChildren(body);
}

function renderOptions(data) {
  titleEl.textContent = T('interact', 'Interact');
  const body = el('div', {});
  data.options.forEach((label, i) => {
    body.append(el('button', {
      class: 'list',
      onclick: () => {
        nui('ktr:optionSelected', { index: i + 1 }); // Lua is 1-indexed
        root.classList.add('hidden');
      },
    }, label));
  });
  screenEl.replaceChildren(body);
}

/* ---------------------------------------------------------------- messages */

window.addEventListener('message', (event) => {
  const { action, data } = event.data || {};
  if (action === 'close') { root.classList.add('hidden'); return; }
  if (action !== 'open' || !data) return;
  if (data.strings) STR = data.strings;
  root.classList.remove('hidden');
  switch (data.screen) {
    case 'wizard': renderWizard(data); break;
    case 'details': renderDetails(data); break;
    case 'poses': renderPoses(data); break;
    case 'confirmRemove': renderConfirmRemove(data); break;
    case 'rotate': renderRotate(data); break;
    case 'options': renderOptions(data); break;
    default: close();
  }
});
