/* Trophy Room NUI — dependency-free. */
'use strict';

const root = document.getElementById('root');
const screenEl = document.getElementById('screen');
const titleEl = document.getElementById('title');

const RESOURCE = (window.GetParentResourceName && window.GetParentResourceName()) || 'kotzu_trophy_room';

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
  titleEl.textContent = 'New Display';
  const state = {
    type: 'mannequin',
    gender: data.playerGender || 'male',
    outfitSource: 'current',
    savedId: null,
    poseId: (data.poses[0] || {}).id || 'neutral',
    platform: 'none',
    weaponKind: 'stand',
    itemName: '',
    label: '',
  };

  const body = el('div', {});

  body.append(el('div', { class: 'section-label' }, 'Display type'));
  const types = [
    { id: 'mannequin', label: 'Mannequin' },
    { id: 'weapon', label: 'Weapon' },
  ];
  body.append(chipRow(types, state.type, (id) => { state.type = id; renderTypeSection(); }));

  const typeSection = el('div', {});
  body.append(typeSection);

  function renderTypeSection() {
    typeSection.replaceChildren();
    if (state.type === 'mannequin') {
      if (!data.manifestBuilt) {
        typeSection.append(el('div', { class: 'warn' },
          'Mannequin assets are not built (manifest v0). Run the asset pipeline first — placement will be refused.'));
      }
      typeSection.append(el('div', { class: 'section-label' }, 'Gender'));
      typeSection.append(chipRow(
        [{ id: 'male', label: 'Male' }, { id: 'female', label: 'Female' }],
        state.gender, (id) => { state.gender = id; }));

      typeSection.append(el('div', { class: 'section-label' }, 'Outfit'));
      const outfitOpts = [
        { id: 'current', label: 'My current outfit' },
        { id: 'none', label: 'Bare mannequin' },
      ];
      if (Array.isArray(data.savedOutfits) && data.savedOutfits.length) {
        outfitOpts.push({ id: 'saved', label: 'Saved outfit…' });
      }
      const savedRow = el('div', {});
      typeSection.append(chipRow(outfitOpts, state.outfitSource, (id) => {
        state.outfitSource = id;
        savedRow.replaceChildren();
        if (id === 'saved') {
          savedRow.append(el('div', { class: 'section-label' }, 'Saved outfits'));
          savedRow.append(chipRow(
            data.savedOutfits.map((o) => ({ id: String(o.id), label: o.label })),
            null, (sid) => { state.savedId = sid; }));
          savedRow.append(el('div', { class: 'note' },
            'Saved-outfit apply depends on your rcore_clothing build; if unsupported the capture of your current outfit is used instead.'));
        }
      }));
      typeSection.append(savedRow);

      typeSection.append(el('div', { class: 'section-label' }, 'Pose'));
      typeSection.append(chipRow(data.poses, state.poseId, (id) => { state.poseId = id; }));

      typeSection.append(el('div', { class: 'section-label' }, 'Stand'));
      typeSection.append(chipRow(data.platforms, state.platform, (id) => { state.platform = id; }));
    } else {
      if (!data.inventoryFunctional) {
        typeSection.append(el('div', { class: 'warn' },
          'No functional inventory bridge detected — weapon displays are disabled.'));
      }
      typeSection.append(el('div', { class: 'section-label' }, 'Mount'));
      typeSection.append(chipRow([
        { id: 'wall', label: 'Wall mount' },
        { id: 'stand', label: 'Floor stand' },
        { id: 'case', label: 'Glass case' },
      ], state.weaponKind, (id) => { state.weaponKind = id; }));
      typeSection.append(el('div', { class: 'section-label' }, 'Weapon item name'));
      typeSection.append(el('input', {
        type: 'text', placeholder: 'weapon_pistol',
        oninput: (e) => { state.itemName = e.target.value; },
      }));
      typeSection.append(el('div', { class: 'note' },
        'The server verifies you own this exact weapon (by serial) and removes it from your inventory atomically. Retrieve it any time from the display.'));
    }
  }
  renderTypeSection();

  body.append(el('div', { class: 'section-label' }, 'Label (optional)'));
  body.append(el('input', {
    type: 'text', maxlength: '48', placeholder: 'e.g. Patrol uniform 2024',
    oninput: (e) => { state.label = e.target.value; },
  }));

  const placeBtn = el('button', {
    class: 'primary',
    onclick: () => {
      if (state.type === 'mannequin') {
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
          itemName: state.itemName.trim(),
          label: state.label,
        });
      }
      root.classList.add('hidden');
    },
  }, 'Start placement');
  body.append(placeBtn);
  body.append(el('div', { class: 'note' },
    'Placement: arrows move · Q/E rotate · PgUp/PgDn height · Shift fine · G ground · Tab snap · X collision · Enter confirm · Backspace cancel'));

  screenEl.replaceChildren(body);
}

/* ------------------------------------------------------------------ others */

function renderDetails(data) {
  titleEl.textContent = data.display.label || 'Display';
  const body = el('div', {});
  for (const line of data.lines || []) {
    body.append(el('div', { class: 'detail-line' }, line));
  }
  body.append(el('div', { class: 'section-label' }, 'Rename'));
  const nameIn = el('input', { type: 'text', maxlength: '48', value: data.display.label || '' });
  const descIn = el('input', { type: 'text', maxlength: '256', value: data.display.description || '', placeholder: 'Description', style: 'margin-top:8px' });
  body.append(nameIn, descIn);
  body.append(el('button', {
    class: 'primary',
    onclick: () => {
      nui('ktr:rename', { uid: data.display.uid, label: nameIn.value, description: descIn.value });
      root.classList.add('hidden');
    },
  }, 'Save'));
  screenEl.replaceChildren(body);
}

function renderPoses(data) {
  titleEl.textContent = 'Pose';
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
  titleEl.textContent = 'Remove display';
  const body = el('div', {});
  body.append(el('div', { class: 'detail-line' }, `Remove "${data.label}"? This cannot be undone.`));
  body.append(el('button', {
    class: 'danger',
    onclick: () => {
      nui('ktr:confirmRemove', { uid: data.uid });
      root.classList.add('hidden');
    },
  }, 'Remove'));
  screenEl.replaceChildren(body);
}

function renderOptions(data) {
  titleEl.textContent = 'Interact';
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
  root.classList.remove('hidden');
  switch (data.screen) {
    case 'wizard': renderWizard(data); break;
    case 'details': renderDetails(data); break;
    case 'poses': renderPoses(data); break;
    case 'confirmRemove': renderConfirmRemove(data); break;
    case 'options': renderOptions(data); break;
    default: close();
  }
});
