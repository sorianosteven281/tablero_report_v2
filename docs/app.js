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
// SECCIÓN FASE 2: CONTROL DE RETORQUEO (SUPERVISOR)
// ==========================================

let currentView = 'map';
const FASE2_STORAGE_KEY = 'toromocho_retorqueo_fase2_v1';
let fase2StatusFilter = 'ALL';
let fase2ZoneFilter = 'ALL';
let fase2SearchQuery = '';

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
    renderFase2View();
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

function getFase2SavedState() {
  try {
    const saved = localStorage.getItem(FASE2_STORAGE_KEY);
    return saved ? JSON.parse(saved) : {};
  } catch (e) {
    return {};
  }
}

function saveFase2State(state) {
  try {
    localStorage.setItem(FASE2_STORAGE_KEY, JSON.stringify(state));
  } catch (e) {}
}

function getFase2Data() {
  if (window.FASE2_DATA && Array.isArray(window.FASE2_DATA)) {
    return window.FASE2_DATA;
  }
  // Fallback filtering 4 digits from ALL_PANELS
  return (window.ALL_PANELS_DATA || []).filter(p => /^\d{4}(?!\d)/.test(p.tag || ''));
}

window.updateFase2Status = function(tag, newStatus) {
  const state = getFase2SavedState();
  if (!state[tag]) state[tag] = {};
  state[tag].status = newStatus;

  // Auto asignar fecha de hoy si se marca como retorqueado
  if (newStatus === 'RETORQUEADO' && !state[tag].date) {
    const now = new Date();
    state[tag].date = now.toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });
  }

  saveFase2State(state);
  updateFase2Metrics();
  renderFase2Cards();
  showToast(tag + ': ' + (newStatus === 'RETORQUEADO' ? '✅ Retorqueado' : newStatus === 'PROCESO' ? '⏳ En Proceso' : '⚪ Pendiente'));
};

window.updateFase2Field = function(tag, field, value) {
  const state = getFase2SavedState();
  if (!state[tag]) state[tag] = {};
  state[tag][field] = value.trim();
  saveFase2State(state);
  updateFase2Metrics();
};

window.locateFase2Panel = function(tag) {
  switchView('map');
  setTimeout(() => {
    selectPanel(tag);
  }, 250);
};

function updateFase2Metrics() {
  const list = getFase2Data();
  const state = getFase2SavedState();
  const total = list.length;
  let done = 0;
  let prog = 0;
  let pend = 0;

  list.forEach(p => {
    const item = state[p.tag] || {};
    const st = item.status || 'PENDIENTE';
    if (st === 'RETORQUEADO') done++;
    else if (st === 'PROCESO') prog++;
    else pend++;
  });

  const percent = total > 0 ? Math.round((done / total) * 100) : 0;

  const elTotal = document.getElementById('f2-metric-total');
  const elDone = document.getElementById('f2-metric-done');
  const elProg = document.getElementById('f2-metric-prog');
  const elPend = document.getElementById('f2-metric-pend');
  const elBar = document.getElementById('f2-progress-bar');
  const elPct = document.getElementById('f2-progress-percent');
  const elCnt = document.getElementById('f2-progress-count');
  const headerBadge = document.getElementById('fase2-header-badge');

  const chipDone = document.getElementById('chip-cnt-done');
  const chipProg = document.getElementById('chip-cnt-prog');
  const chipPend = document.getElementById('chip-cnt-pend');

  if (elTotal) elTotal.innerText = total;
  if (elDone) elDone.innerText = done;
  if (elProg) elProg.innerText = prog;
  if (elPend) elPend.innerText = pend;
  if (elBar) elBar.style.width = percent + '%';
  if (elPct) elPct.innerText = percent + '% completado';
  if (elCnt) elCnt.innerText = done + ' de ' + total + ' tableros retorqueados';
  if (headerBadge) headerBadge.innerText = done + '/' + total;

  if (chipDone) chipDone.innerText = done;
  if (chipProg) chipProg.innerText = prog;
  if (chipPend) chipPend.innerText = pend;
}

function renderFase2Cards() {
  const container = document.getElementById('fase2-cards-container');
  if (!container) return;

  const list = getFase2Data();
  const state = getFase2SavedState();
  const q = fase2SearchQuery.toLowerCase().replace(/[-_ ]/g, '');

  let filtered = list.filter(p => {
    const item = state[p.tag] || {};
    const st = item.status || 'PENDIENTE';

    if (fase2StatusFilter !== 'ALL' && st !== fase2StatusFilter) {
      return false;
    }

    if (fase2ZoneFilter !== 'ALL') {
      const tagUpper = (p.tag || '').toUpperCase();
      if (!tagUpper.startsWith(fase2ZoneFilter)) {
        return false;
      }
    }

    if (q.length > 0) {
      const tagClean = (p.tag || '').toLowerCase().replace(/[-_ ]/g, '');
      const locClean = (p.loc || '').toLowerCase().replace(/[-_ ]/g, '');
      const respClean = (item.resp || p.default_resp || '').toLowerCase().replace(/[-_ ]/g, '');
      const obsClean = (item.obs || p.default_obs || '').toLowerCase().replace(/[-_ ]/g, '');
      if (!tagClean.includes(q) && !locClean.includes(q) && !respClean.includes(q) && !obsClean.includes(q)) {
        return false;
      }
    }

    return true;
  });

  if (filtered.length === 0) {
    container.innerHTML = `
      <div style="padding: 30px; text-align: center; color: var(--text-muted); font-size: 0.9rem; background: var(--panel-bg); border-radius: 12px; border: 1px dashed var(--card-border);">
        <i data-lucide="inbox" size="32" style="margin-bottom: 8px; opacity: 0.5;"></i><br>
        No se encontraron tableros que coincidan con los filtros aplicados.
      </div>`;
    if (window.lucide) lucide.createIcons();
    return;
  }

  let html = '';
  filtered.forEach(p => {
    const tag = p.tag;
    const item = state[tag] || {};
    const st = item.status || 'PENDIENTE';
    const resp = item.resp !== undefined ? item.resp : (p.default_resp || '');
    const date = item.date !== undefined ? item.date : (p.default_crew || '');
    const obs = item.obs !== undefined ? item.obs : (p.default_obs || '');

    const color = resolveColor(p);
    const iconChar = resolveIconChar(p);
    const statusClass = st === 'RETORQUEADO' ? 'status-retorqueado' : st === 'PROCESO' ? 'status-proceso' : 'status-pendiente';
    const optClass = st === 'RETORQUEADO' ? 'opt-retorqueado' : st === 'PROCESO' ? 'opt-proceso' : 'opt-pendiente';

    let thumbHtml = '';
    if (p.photo) {
      thumbHtml = `
        <div class="f2-thumb-wrap" onclick="openPhotoModal('${p.photo}', '${tag}')" title="Ver foto del tablero">
          <img src="${p.photo}" class="f2-thumb-img" loading="lazy" />
        </div>`;
    } else {
      thumbHtml = `
        <div class="f2-thumb-wrap" style="display:flex;align-items:center;justify-content:center;color:#64748b;font-size:11px;background:#0f172a;" title="Sin foto disponible">
          <span>Sin foto</span>
        </div>`;
    }

    const safeResp = resp.replace(/"/g, '&quot;');
    const safeDate = date.replace(/"/g, '&quot;');
    const safeObs = obs.replace(/"/g, '&quot;');

    html += `
      <div class="f2-card ${statusClass}">
        <div class="f2-card-header">
          <div class="f2-tag-wrap">
            <span style="display:inline-flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:50%;background:${color};color:#000;font-size:13px;font-weight:bold;">${iconChar}</span>
            <span class="f2-tag">${tag}</span>
            <span class="f2-badge-type">${p.type || 'TABLERO'}</span>
          </div>
          <select class="f2-status-select ${optClass}" onchange="updateFase2Status('${tag}', this.value)">
            <option value="PENDIENTE" ${st === 'PENDIENTE' ? 'selected' : ''}>⚪ Pendiente</option>
            <option value="PROCESO" ${st === 'PROCESO' ? 'selected' : ''}>⏳ En Proceso</option>
            <option value="RETORQUEADO" ${st === 'RETORQUEADO' ? 'selected' : ''}>✅ Retorqueado</option>
          </select>
        </div>

        <div class="f2-loc"><i data-lucide="map-pin" size="13" style="vertical-align:middle;color:var(--accent);"></i> ${p.loc || 'Planta Concentradora'}</div>

        <div class="f2-card-body">
          ${thumbHtml}
          <div class="f2-form-grid">
            <div class="f2-input-wrap">
              <label>👤 Técnico / Responsable</label>
              <input type="text" class="f2-input" list="fase2-techs" placeholder="Nombre de quien realizó..." value="${safeResp}" oninput="updateFase2Field('${tag}', 'resp', this.value)" />
            </div>
            <div class="f2-input-wrap">
              <label>📅 Fecha / Guardia</label>
              <input type="text" class="f2-input" placeholder="Ej. 30/10/2026 - Guardia A" value="${safeDate}" oninput="updateFase2Field('${tag}', 'date', this.value)" />
            </div>
            <div class="f2-input-wrap" style="grid-column: 1 / -1;">
              <label>📝 Observaciones / Torque</label>
              <input type="text" class="f2-input" placeholder="Ej. Borneras ajustadas a torque, cableado ordenado..." value="${safeObs}" oninput="updateFase2Field('${tag}', 'obs', this.value)" />
            </div>
          </div>
        </div>

        <div class="f2-card-footer">
          ${p.latitude != null ? `<button class="btn-f2-locate" onclick="locateFase2Panel('${tag}')"><i data-lucide="navigation" size="12"></i> Ver en Mapa</button>` : '<span style="font-size:0.7rem;color:#ef4444;">⚠️ Sin GPS</span>'}
        </div>
      </div>`;
  });

  container.innerHTML = html;
  if (window.lucide) lucide.createIcons();
}


function renderFase2View() {
  updateFase2Metrics();
  renderFase2Cards();
}

window.shareFase2WhatsApp = function() {
  const list = getFase2Data();
  const state = getFase2SavedState();
  const total = list.length;
  let done = 0;
  let prog = 0;
  let pend = 0;
  const doneList = [];

  list.forEach(p => {
    const item = state[p.tag] || {};
    const st = item.status || 'PENDIENTE';
    if (st === 'RETORQUEADO') {
      done++;
      const resp = item.resp || p.default_resp || 'Técnico';
      doneList.push(`• *${p.tag}* (${resp})`);
    } else if (st === 'PROCESO') {
      prog++;
    } else {
      pend++;
    }
  });

  const pct = total > 0 ? Math.round((done / total) * 100) : 0;
  const nowStr = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });

  let text = `⚡ *CONTROL DE RETORQUEO — FASE 2*
🏢 *UM CHINALCO TOROMOCHO*
📅 *Fecha:* ${nowStr}
-----------------------------------
📊 *Avance General: ${pct}%*
✅ *Retorqueados:* ${done} de ${total}
⏳ *En Proceso:* ${prog}
⚪ *Pendientes:* ${pend}
-----------------------------------
`;

  if (doneList.length > 0) {
    text += `*Últimos retorqueados:*
${doneList.slice(-10).join('\n')}

`;
  }
  text += `🔗 *Plano y lista en vivo:* https://sorianosteven281.github.io/tablero_report_v2/#fase2`;

  const waUrl = `https://api.whatsapp.com/send?text=${encodeURIComponent(text)}`;
  window.open(waUrl, '_blank');
};

window.exportFase2CSV = function() {
  const list = getFase2Data();
  const state = getFase2SavedState();

  const rows = ['\uFEFFTAG,Ubicacion,Tipo,Estado_Retorqueo,Responsable,Fecha_Guardia,Observaciones,Latitud,Longitud'];
  list.forEach(p => {
    const item = state[p.tag] || {};
    const st = item.status || 'PENDIENTE';
    const resp = item.resp !== undefined ? item.resp : (p.default_resp || '');
    const date = item.date !== undefined ? item.date : (p.default_crew || '');
    const obs = item.obs !== undefined ? item.obs : (p.default_obs || '');

    rows.push([
      `"${(p.tag || '').replace(/"/g, '""')}"`,
      `"${(p.loc || '').replace(/"/g, '""')}"`,
      `"${(p.type || '').replace(/"/g, '""')}"`,
      `"${st}"`,
      `"${resp.replace(/"/g, '""')}"`,
      `"${date.replace(/"/g, '""')}"`,
      `"${obs.replace(/"/g, '""')}"`,
      p.latitude != null ? p.latitude : '',
      p.longitude != null ? p.longitude : ''
    ].join(','));
  });

  downloadFile(rows.join('\r\n'), 'retorqueo_fase2_toromocho.csv', 'text/csv;charset=utf-8;');
};


window.resetFase2Data = function() {
  if (confirm('¿Estás seguro de que deseas reiniciar todos los estados y datos guardados de Retorqueo Fase 2?')) {
    localStorage.removeItem(FASE2_STORAGE_KEY);
    showToast('Datos de retorqueo restablecidos.');
    renderFase2View();
  }
};

// Listeners de búsqueda y filtros en Fase 2
document.addEventListener('DOMContentLoaded', () => {
  const f2SearchInput = document.getElementById('f2-search-input');
  const f2SearchClear = document.getElementById('f2-search-clear');

  if (f2SearchInput) {
    f2SearchInput.addEventListener('input', (e) => {
      fase2SearchQuery = e.target.value.trim();
      if (f2SearchClear) f2SearchClear.style.display = fase2SearchQuery ? 'block' : 'none';
      renderFase2Cards();
    });
  }

  if (f2SearchClear) {
    f2SearchClear.addEventListener('click', () => {
      if (f2SearchInput) {
        f2SearchInput.value = '';
        fase2SearchQuery = '';
        f2SearchClear.style.display = 'none';
        renderFase2Cards();
        f2SearchInput.focus();
      }
    });
  }

  document.querySelectorAll('#f2-status-chips .chip').forEach(chip => {
    chip.addEventListener('click', (e) => {
      document.querySelectorAll('#f2-status-chips .chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      fase2StatusFilter = chip.getAttribute('data-f2-status') || 'ALL';
      renderFase2Cards();
    });
  });

  document.querySelectorAll('#f2-zone-chips .chip').forEach(chip => {
    chip.addEventListener('click', (e) => {
      document.querySelectorAll('#f2-zone-chips .chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      fase2ZoneFilter = chip.getAttribute('data-f2-zone') || 'ALL';
      renderFase2Cards();
    });
  });

  // Inicializar vista basada en URL hash (ej. index.html#fase2)
  if (window.location.hash === '#fase2') {
    switchView('fase2');
  } else {
    updateFase2Metrics();
  }
});
