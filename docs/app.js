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

// Modal de Exportación
const exportModal = document.getElementById('export-modal');
const btnOpenExport = document.getElementById('btn-open-export');
const btnCloseExport = document.getElementById('btn-close-export');

if (btnOpenExport && exportModal) {
  btnOpenExport.addEventListener('click', () => {
    exportModal.style.display = 'flex';
  });
}
if (btnCloseExport && exportModal) {
  btnCloseExport.addEventListener('click', () => {
    exportModal.style.display = 'none';
  });
}
if (exportModal) {
  exportModal.addEventListener('click', (e) => {
    if (e.target === exportModal) exportModal.style.display = 'none';
  });
}

// Impresión Informal de Campo (Tipo Maps)
window.printInformalMap = function() {
  if (exportModal) exportModal.style.display = 'none';
  
  const q = searchQuery.toLowerCase().replace(/[-_ ]/g, '');
  const visible = ALL_PANELS.filter(p => {
    if (p.latitude == null || p.longitude == null) return false;
    if (activeZone !== 'ALL' && activeZone !== 'PENDING') {
      if (!(p.tag || '').toUpperCase().startsWith(activeZone)) return false;
    }
    if (q.length > 0) {
      const cleanTag = (p.tag || '').toLowerCase().replace(/[-_ ]/g, '');
      const cleanLoc = (p.loc || '').toLowerCase().replace(/[-_ ]/g, '');
      if (!cleanTag.includes(q) && !cleanLoc.includes(q)) return false;
    }
    return true;
  });

  const container = document.getElementById('print-container');
  if (!container) return;
  const nowStr = new Date().toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });
  
  let html = '<div class="print-header">' +
               '<h1>UM CHINALCO TOROMOCHO — CROQUIS DE CAMPO DE TABLEROS</h1>' +
               '<div class="print-meta">' +
                 '<span><b>Filtro:</b> ' + (activeZone === 'ALL' ? 'Todos los tableros' : activeZone) + ' | <b>Total:</b> ' + visible.length + ' tableros</span>' +
                 '<span><b>Fecha:</b> ' + nowStr + '</span>' +
               '</div>' +
             '</div>' +
             '<div class="print-grid">';

  visible.forEach(p => {
    const photoSrc = p.photo ? p.photo : 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="90" height="90" viewBox="0 0 24 24" fill="none" stroke="%2394a3b8" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>';
    const note = p.note ? '<div class="print-card-note">📌 <b>Acceso:</b> ' + p.note + '</div>' : '';
    html += '<div class="print-card">' +
              '<img class="print-card-img" src="' + photoSrc + '" />' +
              '<div class="print-card-body">' +
                '<div class="print-card-tag">' + p.tag + '</div>' +
                '<div class="print-card-loc">' + (p.loc || '') + '</div>' +
                '<div class="print-card-gps">GPS: ' + p.latitude.toFixed(6) + ', ' + p.longitude.toFixed(6) + ' (' + (p.type || '') + ')</div>' +
                note +
              '</div>' +
            '</div>';
  });

  html += '</div>';
  container.innerHTML = html;

  setTimeout(() => {
    window.print();
  }, 300);
};

function downloadFile(content, fileName, mimeType) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  if (exportModal) exportModal.style.display = 'none';
  showToast('Descargado: ' + fileName);
}

window.exportData = function(format) {
  const locatedPanels = ALL_PANELS.filter(p => p.latitude != null && p.longitude != null);

  if (format === 'kml') {
    let kml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
              '<kml xmlns="http://www.opengis.net/kml/2.2">\n' +
              '  <Document>\n' +
              '    <name>Tableros Chinalco Toromocho</name>\n' +
              '    <description>Mapeo de tableros eléctricos y salas UM Chinalco</description>\n';
    locatedPanels.forEach(p => {
      const desc = '<![CDATA[' +
        '<b>TAG:</b> ' + p.tag + '<br>' +
        '<b>Ubicación:</b> ' + (p.loc || '') + '<br>' +
        '<b>Tipo:</b> ' + (p.type || '') + '<br>' +
        '<b>Coordenadas:</b> ' + p.latitude + ', ' + p.longitude + '<br>' +
        (p.note ? '<b>Nota:</b> ' + p.note + '<br>' : '') +
      ']]>';
      kml += '    <Placemark>\n' +
             '      <name>' + p.tag + '</name>\n' +
             '      <description>' + desc + '</description>\n' +
             '      <Point>\n' +
             '        <coordinates>' + p.longitude + ',' + p.latitude + ',0</coordinates>\n' +
             '      </Point>\n' +
             '    </Placemark>\n';
    });
    kml += '  </Document>\n</kml>';
    downloadFile(kml, 'tableros_chinalco.kml', 'application/vnd.google-earth.kml+xml;charset=utf-8');
  } 
  else if (format === 'csv') {
    const rows = ['\uFEFFTAG,Ubicacion,Tipo,Latitud,Longitud,Color,Icono,Nota,Foto,Ultima_Inspeccion'];
    ALL_PANELS.forEach(p => {
      rows.push([
        '"' + (p.tag || '').replace(/"/g, '""') + '"',
        '"' + (p.loc || '').replace(/"/g, '""') + '"',
        '"' + (p.type || '').replace(/"/g, '""') + '"',
        p.latitude != null ? p.latitude : '',
        p.longitude != null ? p.longitude : '',
        '"' + (p.color || '') + '"',
        '"' + (p.icon || '') + '"',
        '"' + (p.note || '').replace(/"/g, '""') + '"',
        '"' + (p.photo || '') + '"',
        '"' + (p.last_inspected_at || '') + '"'
      ].join(','));
    });
    downloadFile(rows.join('\r\n'), 'tableros_chinalco.csv', 'text/csv;charset=utf-8;');
  }
  else if (format === 'geojson') {
    const geojson = {
      type: "FeatureCollection",
      features: locatedPanels.map(p => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [p.longitude, p.latitude]
        },
        properties: {
          tag: p.tag,
          loc: p.loc,
          type: p.type,
          color: p.color,
          icon: p.icon,
          note: p.note,
          photo: p.photo,
          last_inspected_at: p.last_inspected_at
        }
      }))
    };
    downloadFile(JSON.stringify(geojson, null, 2), 'tableros_chinalco.geojson', 'application/geo+json;charset=utf-8');
  }
  else if (format === 'json') {
    downloadFile(JSON.stringify(ALL_PANELS, null, 2), 'panels.json', 'application/json;charset=utf-8');
  }
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
