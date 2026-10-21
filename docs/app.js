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
