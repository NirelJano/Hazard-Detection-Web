// ============================================
// Dashboard Filters Module
// ============================================

// ---------- Filter State ----------
export const activeFilters = {
    hazardType: '',
    id: '',
    location: '',
    status: '',
    dateFrom: '',
    dateTo: '',
    reportedBy: ''
};

let onFilterChangeCallback = null;

export function setupFilters(onFilterChange) {
    onFilterChangeCallback = onFilterChange;

    // Mobile toggle
    const toggleBtn = document.getElementById('filters-toggle-btn');
    const section = document.getElementById('filters-section');
    if (toggleBtn && section) {
        toggleBtn.addEventListener('click', () => {
            section.classList.toggle('open');
        });
    }

    // Filter inputs — debounce text inputs, instant for selects/dates
    const debounceMs = 300;
    let debounceTimer = null;

    const textInputs = ['filter-id', 'filter-location', 'filter-reported-by'];
    const instantInputs = ['filter-hazard-type', 'filter-status', 'filter-date-from', 'filter-date-to'];

    textInputs.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            el.addEventListener('input', () => {
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => {
                    readFilterValues();
                    if (onFilterChangeCallback) onFilterChangeCallback();
                }, debounceMs);
            });
        }
    });

    instantInputs.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            el.addEventListener('change', () => {
                readFilterValues();
                if (onFilterChangeCallback) onFilterChangeCallback();
            });
        }
    });

    // Clear filters button
    const clearBtn = document.getElementById('clear-filters-btn');
    if (clearBtn) {
        clearBtn.addEventListener('click', clearFilters);
    }

    // Date constraints
    const dateFromEl = document.getElementById('filter-date-from');
    const dateToEl = document.getElementById('filter-date-to');

    // Set 'today' in local time
    const now = new Date();
    const tzOffset = now.getTimezoneOffset() * 60000;
    const today = new Date(now.getTime() - tzOffset).toISOString().split('T')[0];

    if (dateFromEl) {
        dateFromEl.max = today;
    }
    if (dateToEl) {
        dateToEl.min = today;
    }
}

function readFilterValues() {
    activeFilters.hazardType = (document.getElementById('filter-hazard-type')?.value || '').trim();
    activeFilters.id = (document.getElementById('filter-id')?.value || '').trim();
    activeFilters.location = (document.getElementById('filter-location')?.value || '').trim();
    activeFilters.status = (document.getElementById('filter-status')?.value || '').trim();
    activeFilters.dateFrom = (document.getElementById('filter-date-from')?.value || '').trim();
    activeFilters.dateTo = (document.getElementById('filter-date-to')?.value || '').trim();
    activeFilters.reportedBy = (document.getElementById('filter-reported-by')?.value || '').trim();
}

function clearFilters() {
    document.getElementById('filter-hazard-type').value = '';
    document.getElementById('filter-id').value = '';
    document.getElementById('filter-location').value = '';
    document.getElementById('filter-status').value = '';
    document.getElementById('filter-date-from').value = '';
    document.getElementById('filter-date-to').value = '';
    document.getElementById('filter-reported-by').value = '';

    Object.keys(activeFilters).forEach(k => activeFilters[k] = '');
    if (onFilterChangeCallback) onFilterChangeCallback();
}

// Parse "DD/MM/YY HH:MM" or Firestore Timestamps → Date object
export function parseReportDate(dateVal) {
    if (!dateVal) return null;
    
    // Handle Firestore Timestamps
    if (typeof dateVal === 'object' && dateVal.toDate) {
        return dateVal.toDate();
    }
    
    if (typeof dateVal !== 'string') {
        const d = new Date(dateVal);
        return isNaN(d.getTime()) ? null : d;
    }

    // Try DD/MM/YY HH:MM
    const match = dateVal.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})\s*(\d{1,2}):(\d{2})$/);
    if (match) {
        let [, day, month, year, hours, minutes] = match;
        year = parseInt(year);
        if (year < 100) year += 2000;
        return new Date(year, parseInt(month) - 1, parseInt(day), parseInt(hours), parseInt(minutes));
    }

    // Fallback: try native parsing
    const d = new Date(dateVal);
    return isNaN(d.getTime()) ? null : d;
}

export function applyFilters(reports) {
    return reports.filter(report => {
        // Hazard type — exact
        if (activeFilters.hazardType && (report.hazardType || '') !== activeFilters.hazardType) {
            return false;
        }

        // ID — partial string match
        if (activeFilters.id) {
            const rid = String(report.id || '');
            if (!rid.includes(activeFilters.id)) return false;
        }

        // Location — case-insensitive substring
        if (activeFilters.location) {
            const addr = (report.address || '').toLowerCase();
            if (!addr.includes(activeFilters.location.toLowerCase())) return false;
        }

        // Status — exact
        if (activeFilters.status && (report.status || '') !== activeFilters.status) {
            return false;
        }

        // Reported by — case-insensitive substring
        if (activeFilters.reportedBy) {
            const rb = (report.reportedBy || '').toLowerCase();
            if (!rb.includes(activeFilters.reportedBy.toLowerCase())) return false;
        }

        // Date range
        if (activeFilters.dateFrom || activeFilters.dateTo) {
            const reportDate = parseReportDate(report.date || '');
            if (!reportDate) return false;

            if (activeFilters.dateFrom) {
                const from = new Date(activeFilters.dateFrom);
                if (!isNaN(from.getTime())) {
                    from.setHours(0, 0, 0, 0);
                    if (reportDate < from) return false;
                }
            }
            if (activeFilters.dateTo) {
                const to = new Date(activeFilters.dateTo);
                if (!isNaN(to.getTime())) {
                    to.setHours(23, 59, 59, 999);
                    if (reportDate > to) return false;
                }
            }
        }

        return true;
    });
}

export function getActiveFilterCount() {
    return Object.values(activeFilters).filter(v => v !== '').length;
}

export function updateFilterBadge() {
    const badge = document.getElementById('filter-active-badge');
    if (!badge) return;
    const count = getActiveFilterCount();
    if (count > 0) {
        badge.textContent = count;
        badge.classList.remove('hidden');
    } else {
        badge.classList.add('hidden');
    }
}

export function populateFilterOptions(reports) {
    const select = document.getElementById('filter-hazard-type');
    if (!select) return;

    const currentValue = select.value;
    const types = [...new Set(reports.map(r => r.hazardType).filter(Boolean))].sort();

    // Rebuild options
    select.innerHTML = '<option value="">All Types</option>';
    types.forEach(t => {
        const opt = document.createElement('option');
        opt.value = t;
        opt.textContent = t;
        select.appendChild(opt);
    });

    // Restore selection
    if (currentValue && types.includes(currentValue)) {
        select.value = currentValue;
    }
}
