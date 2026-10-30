let ALL_PANELS = window.ALL_PANELS_DATA || [];

const map = L.map('map', {
  center: [-11.6685, -76.1455],
  zoom: 16.5,
  maxZoom: 21,
  zoomControl: false
});
L.control.zoom({ position: 'bottomleft' }).addTo(map);

const layers = {
  google_hybrid: L.tileLayer('https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}', {
    maxZoom: 21, maxNativeZoom: 19, subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
  }),
  google_sat: L.tileLayer('https://{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', {
    maxZoom: 21, maxNativeZoom: 19, subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
  }),
  esri: L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    maxZoom: 21, maxNativeZoom: 17
  }),
  osm: L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19
  })
};
layers.google_hybrid.addTo(map);

document.querySelectorAll('.layer-btn').forEach(btn => {
  btn.addEventListener('click', (e) => {
    document.querySelectorAll('.layer-btn').forEach(b => b.classList.remove('active'));
    e.target.classList.add('active');
    const layerKey = e.target.getAttribute('data-layer');
    Object.values(layers).forEach(l => map.removeLayer(l));
    if (layers[layerKey]) layers[layerKey].addTo(map);
  });
});

function showToast(msg) {
  const toast = document.getElementById('toast');
  if (!toast) return;
  toast.innerText = msg;
  toast.style.display = 'block';
  setTimeout(() => { toast.style.display = 'none'; }, 2500);
}

function copyCoords(lat, lng) {
  const text = lat.toFixed(6) + ', ' + lng.toFixed(6);
  if (navigator.clipboard) {
    navigator.clipboard.writeText(text).then(() => {
      showToast('✅ Coordenadas GPS copiadas: ' + text);
    }).catch(() => {
      showToast('GPS: ' + text);
    });
  } else {
    showToast('GPS: ' + text);
  }
}

window.openPhotoModal = function(src, tag) {
  const img = document.getElementById('photo-modal-img');
  const cap = document.getElementById('photo-modal-caption');
  const modal = document.getElementById('photo-modal');
  if (img) img.src = src;
  if (cap) cap.innerText = '📷 Tablero ' + tag + ' (Inspección de Mantenimiento)';
  if (modal) modal.style.display = 'flex';
};

window.closePhotoModal = function() {
  const modal = document.getElementById('photo-modal');
  if (modal) modal.style.display = 'none';
};

function resolveColor(p) {
  if (p.color && p.color.length > 0) return p.color;
  const t = (p.tag || '').toUpperCase();
  const l = (p.loc || '').toUpperCase();
  if (t.startsWith('400') || l.includes('SILO')) return '#8B5CF6';
  if (t.startsWith('2615') || t.startsWith('2610') || l.includes('CAL')) return '#EAB308';
  if (t.startsWith('255') || t.startsWith('256') || l.includes('RELAVE') || l.includes('GEHO')) return '#EF4444';
  if (t.startsWith('245') || t.startsWith('240') || l.includes('FILTR')) return '#10B981';
  if (t.startsWith('2214') || t.startsWith('2210') || l.includes('FLOTAC')) return '#0284C7';
  if (t.startsWith('2212') || t.startsWith('2215') || l.includes('REMOLIENDA')) return '#06B6D4';
  if (t.startsWith('2115') || l.includes('PEBBLE')) return '#D97706';
  if (t.startsWith('2110') || l.includes('MOLIENDA')) return '#F59E0B';
  if (t.startsWith('200') || t.startsWith('210') || l.includes('FAJA')) return '#94A3B8';
  return '#38BDF8';
}

function resolveIconChar(p) {
  const iconKey = p.icon || '';
  if (iconKey === 'room') return '🚪';
  if (iconKey === 'container') return '📦';
  if (iconKey === 'pump') return '⚙️';
  if (iconKey === 'substation') return '🔌';
  if (iconKey === 'refugio') return '🛡️';
  if (iconKey === 'faja') return '🏗️';
  if (iconKey === 'taller') return '🔧';

  const l = (p.loc || '').toUpperCase();
  const t = (p.tag || '').toUpperCase();
  if (l.includes('CONTAINER') || l.includes('MODULO')) return '📦';
  if (l.includes('SALA') || l.includes('ER-')) return '🚪';
  if (l.includes('BOMBA') || l.includes('GEHO') || t.includes('PP')) return '⚙️';
  if (l.includes('SUBESTACION') || t.includes('US-')) return '🔌';
  if (t.includes('REFUGIO')) return '🛡️';
  return '⚡';
}

const markersLayer = L.layerGroup().addTo(map);
const markerRegistry = {};
let activeZone = 'ALL';
let searchQuery = '';

function updateStats() {
  const total = ALL_PANELS.length;
  const located = ALL_PANELS.filter(p => p.latitude != null && p.longitude != null).length;
  const pending = total - located;
  const badge = document.getElementById('stats-badge');
  if (badge) {
    badge.innerHTML = '<i data-lucide="check-circle-2" size="13"></i> <span>' + located + ' / ' + total + ' Ubicados</span>';
  }
  const pendingChip = document.querySelector('.chip-pending');
  if (pendingChip) {
    pendingChip.innerText = '⚠️ Pendientes (' + pending + ')';
  }
  if (window.lucide) lucide.createIcons();
}

function renderMarkers() {
  markersLayer.clearLayers();
  Object.keys(markerRegistry).forEach(k => delete markerRegistry[k]);
  const q = searchQuery.toLowerCase().replace(/[-_ ]/g, '');

  ALL_PANELS.forEach(p => {
    const isLocated = (p.latitude != null && p.longitude != null);
    if (activeZone === 'PENDING') return;
    if (!isLocated) return;

    if (activeZone !== 'ALL') {
      const t = (p.tag || '').toUpperCase();
      if (!t.startsWith(activeZone)) return;
    }

    if (q.length > 0) {
      const cleanTag = (p.tag || '').toLowerCase().replace(/[-_ ]/g, '');
      const cleanLoc = (p.loc || '').toLowerCase().replace(/[-_ ]/g, '');
      if (!cleanTag.includes(q) && !cleanLoc.includes(q)) return;
    }

    const color = resolveColor(p);
    const iconChar = resolveIconChar(p);

    const customIcon = L.divIcon({
      className: '',
      html: '<div class="custom-marker" style="--marker-color: ' + color + ';">' +
              '<div class="marker-badge">' + p.tag + '</div>' +
              '<div class="marker-pin">' + iconChar + '</div>' +
            '</div>',
      iconSize: [80, 50],
      iconAnchor: [40, 48]
    });

    const m = L.marker([p.latitude, p.longitude], { icon: customIcon });

    const gmapsUrl = 'https://www.google.com/maps/search/?api=1&query=' + p.latitude + ',' + p.longitude;
    const waText = encodeURIComponent('📍 *Tablero ' + p.tag + '* (' + (p.loc || '') + ')\nTipo: ' + (p.type || '') + '\nGPS: ' + p.latitude.toFixed(6) + ', ' + p.longitude.toFixed(6) + '\nVer mapa: ' + gmapsUrl);
    const waUrl = 'https://api.whatsapp.com/send?text=' + waText;
    const noteHtml = p.note ? '<div class="popup-note">📌 <b>Nota:</b> ' + p.note + '</div>' : '';
    
    let photoHtml = '';
    if (p.photo) {
      photoHtml = '<div class="popup-photo-wrap" onclick="openPhotoModal(\'' + p.photo + '\', \'' + p.tag + '\')" title="Clic para ampliar foto">' +
                    '<img src="' + p.photo + '" class="popup-photo-img" loading="lazy" />' +
                    '<div class="popup-photo-badge">📷 Ampliar foto</div>' +
                  '</div>';
    }

    m.bindPopup(
      '<div class="popup-box">' +
        '<div class="popup-tag">' + p.tag + '</div>' +
        '<div class="popup-loc">' + (p.loc || '') + '</div>' +
        photoHtml +
        '<div class="popup-info"><b>Tipo:</b> ' + (p.type || '') + '</div>' +
        '<div class="popup-info"><b>GPS:</b> ' + p.latitude.toFixed(6) + ', ' + p.longitude.toFixed(6) + '</div>' +
        noteHtml +
        '<div class="popup-actions">' +
          '<button class="btn-pop btn-pop-copy" onclick="copyCoords(' + p.latitude + ', ' + p.longitude + ')">📋 Copiar GPS</button>' +
          '<a class="btn-pop btn-pop-wa" href="' + waUrl + '" target="_blank">💬 WhatsApp</a>' +
          '<a class="btn-pop btn-pop-maps" href="' + gmapsUrl + '" target="_blank">🧭 Abrir en Google Maps</a>' +
        '</div>' +
      '</div>'
    );

    markersLayer.addLayer(m);
    markerRegistry[p.tag] = m;
  });
}

// Buscador interactivo
const searchInput = document.getElementById('search-input');
const searchClear = document.getElementById('search-clear');
const searchDropdown = document.getElementById('search-dropdown');

function updateSearchDropdown() {
  if (!searchInput || !searchDropdown) return;
  const q = searchInput.value.trim().toLowerCase().replace(/[-_ ]/g, '');
  if (q.length === 0) {
    searchDropdown.style.display = 'none';
    searchDropdown.innerHTML = '';
    if (searchClear) searchClear.style.display = 'none';
    return;
  }

  if (searchClear) searchClear.style.display = 'block';
  const matches = ALL_PANELS.filter(p => {
    const cleanTag = (p.tag || '').toLowerCase().replace(/[-_ ]/g, '');
    const cleanLoc = (p.loc || '').toLowerCase().replace(/[-_ ]/g, '');
    return cleanTag.includes(q) || cleanLoc.includes(q);
  }).slice(0, 10);

  if (matches.length === 0) {
    searchDropdown.innerHTML = '<div style="padding:10px; color:#94a3b8; font-size:0.8rem; text-align:center;">No se encontraron tableros</div>';
    searchDropdown.style.display = 'block';
    return;
  }

  searchDropdown.innerHTML = matches.map(p => {
    const isLoc = (p.latitude != null && p.longitude != null);
    const photoIcon = p.photo ? ' 📷' : '';
    const statusHtml = isLoc ? '<span style="color:#10b981; font-size:0.75rem;">📍 Ubicado' + photoIcon + '</span>' : '<span style="color:#ef4444; font-size:0.75rem;">⚠️ Sin GPS</span>';
    return '<div class="search-item" onclick="selectPanel(\'' + p.tag + '\')">' +
             '<div>' +
               '<div class="search-item-tag">' + p.tag + '</div>' +
               '<div class="search-item-loc">' + (p.loc || '') + '</div>' +
             '</div>' +
             statusHtml +
           '</div>';
  }).join('');
  searchDropdown.style.display = 'block';
}

if (searchInput) {
  searchInput.addEventListener('input', (e) => {
    searchQuery = e.target.value.trim();
    updateSearchDropdown();
    renderMarkers();
  });
}

if (searchClear) {
  searchClear.addEventListener('click', () => {
    if (searchInput) searchInput.value = '';
    searchQuery = '';
    updateSearchDropdown();
    renderMarkers();
    if (searchInput) searchInput.focus();
  });
}

window.selectPanel = function(tag) {
  if (searchDropdown) searchDropdown.style.display = 'none';
  const p = ALL_PANELS.find(x => x.tag === tag);
  if (!p) return;

  if (p.latitude != null && p.longitude != null) {
    map.flyTo([p.latitude, p.longitude], 19, { duration: 1.2 });
    setTimeout(() => {
      if (markerRegistry[p.tag]) {
        markerRegistry[p.tag].openPopup();
      }
    }, 1300);
  } else {
    alert('El tablero ' + p.tag + ' (' + (p.loc || '') + ') aún no ha sido geolocalizado en campo.');
  }
};

document.addEventListener('click', (e) => {
  const card = document.querySelector('.controls-card');
  if (card && !card.contains(e.target)) {
    if (searchDropdown) searchDropdown.style.display = 'none';
  }
});

document.querySelectorAll('.chip').forEach(chip => {
  chip.addEventListener('click', (e) => {
    document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
    e.target.classList.add('active');
    activeZone = e.target.getAttribute('data-zone') || 'ALL';
    renderMarkers();
  });
});

// Geolocalización del operador
let myLocMarker = null;
const btnLoc = document.getElementById('btn-my-loc');
if (btnLoc) {
  btnLoc.addEventListener('click', () => {
    if (!navigator.geolocation) {
      alert('Geolocalización no soportada en este navegador.');
      return;
    }
    showToast('Obteniendo posición GPS...');
    navigator.geolocation.getCurrentPosition((pos) => {
      const lat = pos.coords.latitude;
      const lng = pos.coords.longitude;
      map.flyTo([lat, lng], 18.5);
      if (myLocMarker) map.removeLayer(myLocMarker);
      myLocMarker = L.circleMarker([lat, lng], {
        radius: 9, fillColor: '#0284c7', color: '#fff', weight: 3, fillOpacity: 1
      }).addTo(map);
      showToast('📍 Tu posición GPS actual fijada en el mapa');
    }, (err) => {
      alert('No se pudo obtener la ubicación GPS: ' + err.message);
    }, { enableHighAccuracy: true });
  });
}

// Impresión Directa del Plano Satelital para Campo
window.printMapDirectly = function() {
  const q = searchQuery.toLowerCase().replace(/[-_ ]/g, '');
  const bounds = [];
  let visibleCount = 0;

  ALL_PANELS.forEach(p => {
    if (p.latitude != null && p.longitude != null) {
      if (activeZone === 'ALL' || (p.tag || '').toUpperCase().startsWith(activeZone)) {
        if (!q || (p.tag || '').toLowerCase().replace(/[-_ ]/g, '').includes(q) || (p.loc || '').toLowerCase().replace(/[-_ ]/g, '').includes(q)) {
          bounds.push([p.latitude, p.longitude]);
          visibleCount++;
        }
      }
    }
  });

  const metaText = document.getElementById('print-meta-text');
  const nowStr = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });
  const zoneName = activeZone === 'ALL' ? 'Toda la Planta' : ('Zona ' + activeZone);
  if (metaText) {
    metaText.innerText = zoneName + ' | ' + visibleCount + ' tableros visibles | ' + nowStr;
  }

  // Ajustar cámara para que todos los puntos de la zona entren en la hoja
  if (bounds.length > 0) {
    map.fitBounds(bounds, { padding: [40, 40] });
  }

  showToast('Preparando plano satelital para impresión...');

  // Dar tiempo para que Leaflet renderice teselas completas en el nuevo zoom
  setTimeout(() => {
    window.print();
  }, 600);
};

// Respaldo dinámico si data.js estuviese vacío
if (ALL_PANELS.length === 0) {
  fetch('panels.json')
    .then(r => r.json())
    .then(data => {
      if (Array.isArray(data) && data.length > 0) {
        ALL_PANELS = data;
        updateStats();
        renderMarkers();
      }
    })
    .catch(e => console.error('Error fetching panels.json:', e));
} else {
  updateStats();
  renderMarkers();
}

if (window.lucide) lucide.createIcons();



// ==========================================
// SECCIÓN FASE 2: LISTA SIMPLE DE RETORQUEO
// ==========================================

let currentView = 'map';
const F2_STORAGE = 'retorqueo_fase2_checklist_v1';
let f2Filter = 'ALL'; // ALL | PEND | DONE
let f2Search = '';

function getF2State() {
  try {
    return JSON.parse(localStorage.getItem(F2_STORAGE) || '{}');
  } catch (e) {
    return {};
  }
}

function saveF2State(st) {
  try {
    localStorage.setItem(F2_STORAGE, JSON.stringify(st));
  } catch (e) {}
}

function getFase2Data() {
  if (window.FASE2_DATA && Array.isArray(window.FASE2_DATA)) {
    return window.FASE2_DATA;
  }
  return (window.ALL_PANELS_DATA || []).filter(p => /^\d{4}(?!\d)/.test(p.tag || ''));
}

window.switchView = function(viewName) {
  currentView = viewName;
  const tabMap = document.getElementById('tab-btn-map');
  const tabF2 = document.getElementById('tab-btn-fase2');
  const f2View = document.getElementById('fase2-view');
  const controlsCard = document.querySelector('.controls-card');
  const btnLoc = document.getElementById('btn-my-loc');
  const layerSwitcher = document.querySelector('.layer-switcher');
  const printBtn = document.getElementById('btn-print-map');

  if (viewName === 'fase2') {
    if (tabMap) tabMap.classList.remove('active');
    if (tabF2) tabF2.classList.add('active');
    if (f2View) f2View.classList.add('active');
    if (controlsCard) controlsCard.style.display = 'none';
    if (btnLoc) btnLoc.style.display = 'none';
    if (layerSwitcher) layerSwitcher.style.display = 'none';
    if (printBtn) printBtn.style.display = 'none';
    renderF2List();
    if (window.location.hash !== '#fase2') {
      window.history.replaceState(null, null, '#fase2');
    }
  } else {
    if (tabMap) tabMap.classList.add('active');
    if (tabF2) tabF2.classList.remove('active');
    if (f2View) f2View.classList.remove('active');
    if (controlsCard) controlsCard.style.display = 'flex';
    if (btnLoc) btnLoc.style.display = 'flex';
    if (layerSwitcher) layerSwitcher.style.display = 'flex';
    if (printBtn) printBtn.style.display = 'inline-flex';
    if (window.location.hash === '#fase2') {
      window.history.replaceState(null, null, '#');
    }
    setTimeout(() => { if (window.map) map.invalidateSize(); }, 200);
  }
};

function updateF2Metrics() {
  const all = getFase2Data();
  const state = getF2State();
  const total = all.length;
  let done = 0;

  all.forEach(p => {
    if (state[p.tag] && state[p.tag].done) done++;
  });

  const pend = total - done;
  const percent = total > 0 ? Math.round((done / total) * 100) : 0;

  const headerBadge = document.getElementById('fase2-header-badge');
  const counterBadge = document.getElementById('f2-counter-badge');
  const barFill = document.getElementById('f2-bar-fill');
  const cntPend = document.getElementById('cnt-pend');
  const cntDone = document.getElementById('cnt-done');

  if (headerBadge) headerBadge.innerText = done + '/' + total;
  if (counterBadge) counterBadge.innerText = done + ' / ' + total + ' Listos (' + percent + '%)';
  if (barFill) barFill.style.width = percent + '%';
  if (cntPend) cntPend.innerText = pend;
  if (cntDone) cntDone.innerText = done;
}

window.renderF2List = function() {
  const container = document.getElementById('f2-checklist');
  if (!container) return;

  updateF2Metrics();
  const state = getF2State();
  const all = getFase2Data();

  const filtered = all.filter(p => {
    const item = state[p.tag] || {};
    const isDone = !!item.done;
    if (f2Filter === 'PEND' && isDone) return false;
    if (f2Filter === 'DONE' && !isDone) return false;

    if (f2Search) {
      const q = f2Search.toLowerCase();
      const tagMatch = (p.tag || '').toLowerCase().includes(q);
      const locMatch = (p.loc || '').toLowerCase().includes(q);
      const techMatch = (item.tech || '').toLowerCase().includes(q);
      if (!tagMatch && !locMatch && !techMatch) return false;
    }
    return true;
  });

  if (filtered.length === 0) {
    container.innerHTML = '<div style="padding: 30px; text-align: center; color: var(--text-muted); font-size: 0.9rem; background: var(--panel-bg); border-radius: 12px; border: 1px dashed var(--card-border);">' +
      'No se encontraron tableros con el filtro seleccionado.' +
      '</div>';
    return;
  }

  let html = '';
  filtered.forEach((p, idx) => {
    const tag = p.tag;
    const item = state[tag] || {};
    const isDone = !!item.done;
    const tech = item.tech || '';
    const date = item.date || '';
    const hasCoords = p.latitude != null && p.longitude != null;

    html += '<div class="f2-row ' + (isDone ? 'done' : '') + '">' +
      '<input type="checkbox" class="f2-chk" ' + (isDone ? 'checked' : '') + ' onchange="onToggleCheck(\'' + tag + '\', this.checked)" title="Marcar como retorqueado" />' +
      '<div class="f2-num">' + (idx + 1) + '</div>' +
      '<div class="f2-info">' +
        '<div class="f2-tag">' + tag + '</div>' +
        '<div class="f2-loc" title="' + (p.loc || '') + '">' + (p.loc || 'Sin ubicación específica') + '</div>' +
      '</div>' +
      '<input type="text" list="fase2-techs" class="f2-input-tech" placeholder="Técnico..." value="' + tech.replace(/"/g, '&quot;') + '" onchange="onTechChange(\'' + tag + '\', this.value)" />' +
      '<div class="f2-date">' + (date || '-') + '</div>' +
      (hasCoords
        ? '<button class="f2-btn-map" onclick="locateFase2Panel(\'' + tag + '\')" title="Ver en el mapa satelital"><i data-lucide="map-pin" size="16"></i></button>'
        : '<span style="width:24px; text-align:center; opacity:0.3;" title="Sin GPS">📍</span>'
      ) +
    '</div>';
  });

  container.innerHTML = html;
  if (window.lucide) lucide.createIcons();
};

window.onToggleCheck = function(tag, isChecked) {
  const st = getF2State();
  if (!st[tag]) st[tag] = {};
  st[tag].done = isChecked;
  if (isChecked && !st[tag].date) {
    const d = new Date();
    st[tag].date = String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0');
  }
  saveF2State(st);
  renderF2List();
};

window.onTechChange = function(tag, val) {
  const st = getF2State();
  if (!st[tag]) st[tag] = {};
  st[tag].tech = val.trim();
  saveF2State(st);
};

window.setF2Filter = function(filter) {
  f2Filter = filter;
  document.querySelectorAll('.f2-pill').forEach(p => p.classList.remove('active'));
  if (filter === 'ALL') {
    const el = document.getElementById('pill-all');
    if (el) el.classList.add('active');
  }
  if (filter === 'PEND') {
    const el = document.getElementById('pill-pend');
    if (el) el.classList.add('active');
  }
  if (filter === 'DONE') {
    const el = document.getElementById('pill-done');
    if (el) el.classList.add('active');
  }
  renderF2List();
};

window.onF2Search = function(val) {
  f2Search = (val || '').trim().toLowerCase();
  renderF2List();
};

window.locateFase2Panel = function(tag) {
  switchView('map');
  setTimeout(() => {
    selectPanel(tag);
  }, 250);
};

window.shareFase2WhatsApp = function() {
  const all = getFase2Data();
  const state = getF2State();
  const total = all.length;
  let done = 0;
  const doneList = [];

  all.forEach(p => {
    const item = state[p.tag] || {};
    if (item.done) {
      done++;
      doneList.push('• *' + p.tag + '* - ' + (item.tech || 'Sin técnico') + ' (' + (item.date || 'Hoy') + ')');
    }
  });

  const percent = total > 0 ? Math.round((done / total) * 100) : 0;
  const now = new Date();
  const fechaStr = now.toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });

  let msg = '⚡ *CONTROL RETORQUEO FASE 2* ⚡\n';
  msg += '🏢 *UM Chinalco Toromocho*\n';
  msg += '📅 Fecha: ' + fechaStr + '\n';
  msg += '📊 *Avance: ' + done + ' / ' + total + ' (' + percent + '%)*\n';
  msg += '✅ Retorqueados: ' + done + '\n';
  msg += '⚪ Pendientes: ' + (total - done) + '\n\n';

  if (doneList.length > 0) {
    msg += '📋 *Tableros Listos (' + doneList.length + '):*\n';
    msg += doneList.slice(-25).join('\n');
    if (doneList.length > 25) {
      msg += '\n... y ' + (doneList.length - 25) + ' tableros más';
    }
  } else {
    msg += '⚪ *Aún no se registran tableros retorqueados.*';
  }

  const waUrl = 'https://api.whatsapp.com/send?text=' + encodeURIComponent(msg);
  window.open(waUrl, '_blank');
};

window.exportFase2CSV = function() {
  const all = getFase2Data();
  const state = getF2State();
  const rows = ['\uFEFFNro,TAG,Ubicacion,Tipo,Retorqueado,Tecnico,Fecha,Latitud,Longitud'];

  all.forEach((p, idx) => {
    const item = state[p.tag] || {};
    const isDone = item.done ? 'SI' : 'NO';
    const tech = item.tech || '';
    const date = item.date || '';

    rows.push([
      idx + 1,
      '"' + (p.tag || '').replace(/"/g, '""') + '"',
      '"' + (p.loc || '').replace(/"/g, '""') + '"',
      '"' + (p.type || '').replace(/"/g, '""') + '"',
      '"' + isDone + '"',
      '"' + tech.replace(/"/g, '""') + '"',
      '"' + date.replace(/"/g, '""') + '"',
      p.latitude != null ? p.latitude : '',
      p.longitude != null ? p.longitude : ''
    ].join(','));
  });

  const blob = new Blob([rows.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'retorqueo_fase2_' + new Date().toISOString().slice(0, 10) + '.csv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  showToast('📥 Reporte CSV descargado correctamente');
};

window.backupFase2JSON = function() {
  const state = getF2State();
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'backup_retorqueo_' + new Date().toISOString().slice(0, 10) + '.json';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  showToast('💾 Respaldo JSON descargado');
};

window.importFase2JSON = function() {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.json';
  input.onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const data = JSON.parse(evt.target.result);
        if (typeof data === 'object' && data !== null) {
          saveF2State(data);
          renderF2List();
          showToast('✅ Respaldo cargado correctamente');
        } else {
          alert('El archivo no contiene un formato válido.');
        }
      } catch (err) {
        alert('Error al leer el archivo JSON.');
      }
    };
    reader.readAsText(file);
  };
  input.click();
};

window.resetFase2Data = function() {
  if (confirm('¿Deseas reiniciar todos los checks y técnicos del Retorqueo Fase 2?')) {
    localStorage.removeItem(F2_STORAGE);
    showToast('Lista de retorqueo reiniciada.');
    renderF2List();
  }
};

// Inicializar vista según URL hash al cargar
document.addEventListener('DOMContentLoaded', () => {
  if (window.location.hash === '#fase2') {
    switchView('fase2');
  } else {
    updateF2Metrics();
  }
});

if (document.readyState === 'complete' || document.readyState === 'interactive') {
  if (window.location.hash === '#fase2') {
    switchView('fase2');
  } else {
    updateF2Metrics();
  }
}
