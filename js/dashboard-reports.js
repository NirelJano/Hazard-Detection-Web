// ============================================
// Dashboard Reports Module (Log + Pagination)
// ============================================

import { updateMapMarkers, flyToReport } from './dashboard-map.js';
import { applyFilters, updateFilterBadge } from './dashboard-filters.js';

let allReports = [];         // All reports from Firestore (unfiltered)
export let currentReports = [];     // Currently displayed (filtered) reports

// ---------- Pagination State ----------
let currentPage = 1;
let pageSize = 25;

// Helper: resolve image URL for display (handles 'uploading' placeholder)
export function getDisplayImageUrl(imageUrl) {
    if (!imageUrl || imageUrl === 'uploading') return 'assets/icons/icon-192.png';
    return imageUrl;
}

export function setAllReports(reports) {
    allReports = reports;
}

export function renderFilteredReports(resetPage = true) {
    const filtered = applyFilters(allReports);
    currentReports = filtered;

    // Reset to page 1 when filters change
    if (resetPage) currentPage = 1;

    // Update stats (show filtered counts)
    const reportsCount = document.getElementById('reports-count');
    const newCount = document.getElementById('new-count');
    const inProgressCount = document.getElementById('pending-count');
    const fixedCount = document.getElementById('fixed-count');

    if (reportsCount) reportsCount.textContent = filtered.length;
    if (newCount) newCount.textContent = filtered.filter(r => r.status === 'new').length;
    if (inProgressCount) inProgressCount.textContent = filtered.filter(r => r.status === 'in-progress').length;
    if (fixedCount) fixedCount.textContent = filtered.filter(r => r.status === 'fixed').length;

    // Pagination calculations
    const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
    if (currentPage > totalPages) currentPage = totalPages;
    const startIdx = (currentPage - 1) * pageSize;
    const endIdx = Math.min(startIdx + pageSize, filtered.length);
    const pageReports = filtered.slice(startIdx, endIdx);

    // Render report table
    const reportsList = document.getElementById('reports-list');
    if (reportsList) {
        if (allReports.length === 0) {
            reportsList.innerHTML = `
          <div class="text-center py-12 text-dark-400">
            <svg class="w-12 h-12 mx-auto mb-3 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
            </svg>
            <p>No reports yet</p>
            <p class="text-sm mt-1">Upload an image or use live detection to create your first report</p>
          </div>`;
        } else if (filtered.length === 0) {
            reportsList.innerHTML = `
          <div class="text-center py-12 text-dark-400">
            <svg class="w-12 h-12 mx-auto mb-3 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
            </svg>
            <p>No reports match the current filters</p>
            <p class="text-sm mt-1">Try adjusting or clearing your filters</p>
          </div>`;
        } else {
            reportsList.innerHTML = `
                <div class="w-full overflow-x-auto">
                    <table class="reports-table">
                        <colgroup>
                            <col style="width: 14%">
                            <col style="width: 12%">
                            <col style="width: 25%">
                            <col style="width: 15%">
                            <col style="width: 8%">
                            <col style="width: 12%">
                            <col style="width: 14%">
                        </colgroup>
                        <thead>
                            <tr class="reports-table-header">
                                <th>ID</th>
                                <th>Hazard Type</th>
                                <th>Location</th>
                                <th>Date</th>
                                <th class="text-center">Image</th>
                                <th>Status</th>
                                <th>Reported By</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${pageReports.map((r) => renderReportRow(r)).join('')}
                        </tbody>
                    </table>
                </div>`;

            // Add click listeners for images
            document.querySelectorAll('.report-img-clickable').forEach(img => {
                img.addEventListener('click', (e) => {
                    openImageModal(e.target.src);
                });
            });

            // Add click listeners for address cells
            document.querySelectorAll('.address-link').forEach(el => {
                el.addEventListener('click', () => {
                    const reportId = el.dataset.reportId;
                    flyToReport(reportId, currentReports);
                });
            });
        }
    }

    // Update pagination controls
    updatePaginationControls(filtered.length, totalPages, startIdx, endIdx);

    // Update map markers with filtered reports
    updateMapMarkers(filtered);

    // Update mobile badge
    updateFilterBadge();
}

function renderReportRow(report) {
    // Format date nicely
    let datePart = '—';
    let timePart = '';
    if (typeof report.date === 'string' && report.date.length > 0) {
        // Expected format: "DD/MM/YY HH:MM"
        const parts = report.date.split(' ');
        if (parts.length >= 2) {
            datePart = parts[0]; // DD/MM/YY
            timePart = parts[1]; // HH:MM
        } else {
            datePart = report.date;
        }
    } else if (report.date?.toDate) {
        const d = report.date.toDate();
        datePart = d.toLocaleDateString('he-IL');
        timePart = d.toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' });
    }

    const statusClass = `badge-${report.status?.replace(' ', '-') || 'new'}`;
    const hasCoords = report.coordinate && report.coordinate.latitude != null;

    // Hazard type color class
    const hazardType = (report.hazardType || 'Unknown').toLowerCase();
    let hazardClass = 'hazard-type-other';
    if (hazardType === 'pothole') hazardClass = 'hazard-type-pothole';
    else if (hazardType === 'crack') hazardClass = 'hazard-type-crack';

    return `
    <tr class="report-row" data-report-id="${report.id || ''}">
      <td class="report-cell"><span class="report-id">#${report.id || '-'}</span></td>
      <td class="report-cell"><span class="report-hazard-type ${hazardClass}">${report.hazardType || 'Unknown'}</span></td>
      <td class="report-cell report-cell-location ${hasCoords ? 'address-link' : ''}" title="${report.address || ''}" data-report-id="${report.id || ''}">
        ${report.address || 'No address'}
      </td>
      <td class="report-cell">
        <div class="report-date">
          <span class="report-date-main">📅 ${datePart}</span>
          ${timePart ? `<span class="report-date-time">🕐 ${timePart}</span>` : ''}
        </div>
      </td>
      <td class="report-cell report-cell-img">
        <img
          src="${getDisplayImageUrl(report.imageUrl)}"
          alt="Hazard"
          class="report-img report-img-clickable"
          loading="lazy"
        />
      </td>
      <td class="report-cell">
        <span class="badge ${statusClass}">${report.status || 'new'}</span>
      </td>
      <td class="report-cell"><span class="report-reporter">${report.reportedBy || 'Unknown'}</span></td>
    </tr>`;
}

// Scroll report table to a specific row and highlight it
// If the report is on a different page, navigate to that page first
export function scrollToReport(reportId) {
    // Check if report is on the current page, if not navigate to correct page
    const idxInFiltered = currentReports.findIndex(r => String(r.id) === String(reportId));
    if (idxInFiltered !== -1) {
        const targetPage = Math.floor(idxInFiltered / pageSize) + 1;
        if (targetPage !== currentPage) {
            currentPage = targetPage;
            renderFilteredReports(false);
        }
    }

    setTimeout(() => {
        const row = document.querySelector(`tr[data-report-id="${reportId}"]`);
        if (row) {
            row.scrollIntoView({ behavior: 'smooth', block: 'center' });
            row.classList.add('report-row-highlight');
            setTimeout(() => {
                row.classList.remove('report-row-highlight');
            }, 2500);
        }
    }, 100);
}

// ---------- Image Modal ----------
export function openImageModal(src) {
    const modal = document.getElementById('image-modal');
    const modalImg = document.getElementById('modal-image');
    if (modal && modalImg) {
        modalImg.src = src;
        modal.classList.remove('hidden');
        setTimeout(() => {
            modal.classList.remove('opacity-0');
        }, 10);
    }
}

export function setupImageModal() {
    const modal = document.getElementById('image-modal');
    const closeBtn = document.getElementById('close-modal-btn');

    if (modal && closeBtn) {
        const closeModal = () => {
            modal.classList.add('opacity-0');
            setTimeout(() => {
                modal.classList.add('hidden');
                document.getElementById('modal-image').src = '';
            }, 300);
        };

        closeBtn.addEventListener('click', closeModal);
        modal.addEventListener('click', (e) => {
            if (e.target === modal) closeModal();
        });
    }
}

// ============================================
// PAGINATION
// ============================================

export function setupPagination() {
    const prevBtn = document.getElementById('pagination-prev');
    const nextBtn = document.getElementById('pagination-next');
    const pageSizeSelect = document.getElementById('page-size-select');

    if (prevBtn) {
        prevBtn.addEventListener('click', () => {
            if (currentPage > 1) {
                currentPage--;
                renderFilteredReports(false);
                scrollReportsToTop();
            }
        });
    }

    if (nextBtn) {
        nextBtn.addEventListener('click', () => {
            const totalPages = Math.ceil(currentReports.length / pageSize);
            if (currentPage < totalPages) {
                currentPage++;
                renderFilteredReports(false);
                scrollReportsToTop();
            }
        });
    }

    if (pageSizeSelect) {
        pageSizeSelect.addEventListener('change', () => {
            pageSize = parseInt(pageSizeSelect.value) || 25;
            currentPage = 1;
            renderFilteredReports(false);
            scrollReportsToTop();
        });
    }
}

function updatePaginationControls(totalFiltered, totalPages, startIdx, endIdx) {
    const controls = document.getElementById('pagination-controls');
    const infoText = document.getElementById('pagination-info-text');
    const pageInfo = document.getElementById('pagination-page-info');
    const prevBtn = document.getElementById('pagination-prev');
    const nextBtn = document.getElementById('pagination-next');

    if (!controls) return;

    if (totalFiltered === 0) {
        controls.classList.add('hidden');
        return;
    }

    controls.classList.remove('hidden');

    if (infoText) {
        infoText.textContent = `Showing ${startIdx + 1}–${endIdx} of ${totalFiltered}`;
    }
    if (pageInfo) {
        pageInfo.textContent = `Page ${currentPage} / ${totalPages}`;
    }
    if (prevBtn) {
        prevBtn.disabled = currentPage <= 1;
    }
    if (nextBtn) {
        nextBtn.disabled = currentPage >= totalPages;
    }
}

function scrollReportsToTop() {
    const reportsList = document.getElementById('reports-list');
    if (reportsList) {
        reportsList.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
}
