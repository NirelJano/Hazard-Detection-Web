// ============================================
// Dashboard Reports Module (Log + Pagination)
// ============================================

import { db } from '../firebase-config.js';
import { updateMapMarkers, flyToReport } from './dashboard-map.js';
import { applyFilters, updateFilterBadge, parseReportDate } from './dashboard-filters.js';
import {
    doc,
    writeBatch,
    updateDoc
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { showToast } from './app.js';

let allReports = [];         // All reports from Firestore (unfiltered)
export let currentReports = [];     // Currently displayed (filtered) reports

// ---------- Pagination State ----------
let currentPage = 1;
let pageSize = 25;

// ---------- Sorting State ----------
export let currentSortColumn = 'id';
export let currentSortDirection = 'desc'; // 'asc' or 'desc'

// ---------- Admin State ----------
let _isAdmin = false;
let selectedIds = new Set();   // Set of report docIds currently checked
let _showAllMarkers = false;   // Admin toggle: show all markers on map

// Helper: resolve image URL for display (handles 'uploading' placeholder)
// Optionally applies Cloudinary thumbnail transforms for bandwidth savings
export function getDisplayImageUrl(imageUrl, { thumbnail = true } = {}) {
    if (!imageUrl || imageUrl === 'uploading') return 'assets/icons/icon-192.png';
    // Apply Cloudinary blurry thumbnail transforms if URL is from Cloudinary
    // Serves a tiny blurred placeholder (~2-3KB) instead of full image (2-5MB)
    if (thumbnail && imageUrl.includes('res.cloudinary.com') && imageUrl.includes('/upload/')) {
        return imageUrl.replace('/upload/', '/upload/w_40,h_40,c_fill,f_auto,q_30,e_blur:600/');
    }
    return imageUrl;
}

export function setAllReports(reports) {
    allReports = reports;
}

// ---------- Admin Toolbar Setup ----------
export function setupAdminToolbar(isAdmin) {
    _isAdmin = isAdmin;
    const toolbar = document.getElementById('admin-toolbar');
    if (!toolbar) return;

    if (!isAdmin) {
        toolbar.classList.add('hidden');
        return;
    }

    toolbar.classList.remove('hidden');

    // Bulk status change
    const bulkStatusBtn = document.getElementById('bulk-status-btn');
    const bulkStatusSelect = document.getElementById('bulk-status-select');
    const applyStatusBtn = document.getElementById('apply-status-btn');
    const cancelStatusBtn = document.getElementById('cancel-status-btn');

    if (bulkStatusBtn && bulkStatusSelect) {
        bulkStatusBtn.addEventListener('click', () => {
            if (selectedIds.size === 0) {
                showToast('Select at least one report first', 'info');
                return;
            }
            bulkStatusSelect.classList.toggle('hidden');
            if (applyStatusBtn) applyStatusBtn.classList.toggle('hidden');
            if (cancelStatusBtn) cancelStatusBtn.classList.toggle('hidden');
        });

        if (applyStatusBtn) {
            applyStatusBtn.addEventListener('click', async () => {
                const newStatus = bulkStatusSelect.value;
                if (!newStatus) return;
                await bulkUpdateStatus(newStatus);
                bulkStatusSelect.classList.add('hidden');
                applyStatusBtn.classList.add('hidden');
                if (cancelStatusBtn) cancelStatusBtn.classList.add('hidden');
            });
        }

        if (cancelStatusBtn) {
            cancelStatusBtn.addEventListener('click', () => {
                bulkStatusSelect.classList.add('hidden');
                applyStatusBtn.classList.add('hidden');
                cancelStatusBtn.classList.add('hidden');
            });
        }
    }

    // Bulk delete button → open confirmation modal
    const deleteSelectedBtn = document.getElementById('delete-selected-btn');
    if (deleteSelectedBtn) {
        deleteSelectedBtn.addEventListener('click', () => {
            if (selectedIds.size === 0) {
                showToast('Select at least one report first', 'info');
                return;
            }
            openDeleteModal();
        });
    }

    // Confirmation modal buttons
    const confirmDeleteBtn = document.getElementById('confirm-delete-btn');
    const cancelDeleteBtn = document.getElementById('cancel-delete-btn');
    const deleteModal = document.getElementById('delete-confirm-modal');

    if (confirmDeleteBtn) {
        confirmDeleteBtn.addEventListener('click', async () => {
            closeDeleteModal();
            await bulkDelete();
        });
    }

    if (cancelDeleteBtn) {
        cancelDeleteBtn.addEventListener('click', closeDeleteModal);
    }

    if (deleteModal) {
        deleteModal.addEventListener('click', (e) => {
            if (e.target === deleteModal) closeDeleteModal();
        });
    }

    // Cloudinary Cleanup (Local API)
    const cleanupBtn = document.getElementById('cleanup-cloudinary-btn');
    if (cleanupBtn) {
        cleanupBtn.addEventListener('click', async () => {
            if (!confirm('This will permanently delete orphaned images from Cloudinary.\n\nNote: This button only works when running the app locally via "node server.js".\n\nContinue?')) return;

            cleanupBtn.disabled = true;
            const originalText = cleanupBtn.innerHTML;
            cleanupBtn.innerHTML = '<div class="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></div> Cleaning...';

            try {
                const res = await fetch('/api/cleanup', { method: 'POST' });

                if (res.status === 404) {
                    showToast('Cleanup API not found. You must run the app locally via "node server.js"', 'error');
                    return;
                }

                const data = await res.json();

                if (data.success) {
                    if (data.deletedCount > 0) {
                        showToast(`Successfully deleted ${data.deletedCount} orphaned images!`, 'success');
                    } else {
                        showToast('All clean! No orphaned images found to delete.', 'info');
                    }
                } else {
                    showToast('Cleanup script failed to run. Check server logs.', 'error');
                }
            } catch (err) {
                console.error('[Admin] Cleanup error:', err);
                showToast('Network error while running cleanup script.', 'error');
            } finally {
                cleanupBtn.disabled = false;
                cleanupBtn.innerHTML = originalText;
            }
        });
    }
}

// ---------- Modal Helpers ----------
function openDeleteModal() {
    const modal = document.getElementById('delete-confirm-modal');
    const countSpan = document.getElementById('delete-count');
    if (countSpan) countSpan.textContent = selectedIds.size;
    if (modal) {
        modal.classList.remove('hidden');
        requestAnimationFrame(() => modal.classList.remove('opacity-0'));
    }
}

function closeDeleteModal() {
    const modal = document.getElementById('delete-confirm-modal');
    if (modal) {
        modal.classList.add('opacity-0');
        setTimeout(() => modal.classList.add('hidden'), 300);
    }
}

// ---------- Bulk Operations ----------
async function bulkUpdateStatus(newStatus) {
    if (selectedIds.size === 0) return;
    try {
        const batch = writeBatch(db);
        selectedIds.forEach(docId => {
            batch.update(doc(db, 'reports', docId), { status: newStatus });
        });
        await batch.commit();

        // Update local state to reflect changes immediately without refresh
        allReports.forEach(report => {
            if (selectedIds.has(report.docId)) {
                report.status = newStatus;
            }
        });

        // Clear selection to reset UI
        clearSelection();

        showToast(`Updated reports to "${newStatus}"`, 'success');
        
        // Force a complete re-render of the table and statistics
        renderFilteredReports(false); 
    } catch (err) {
        console.error('[Admin] Bulk status update error:', err);
        showToast('Failed to update status', 'error');
    }
}

async function updateSingleReportStatus(docId, newStatus) {
    try {
        await updateDoc(doc(db, 'reports', docId), { status: newStatus });

        // Update local state
        const report = allReports.find(r => r.docId === docId);
        if (report) {
            report.status = newStatus;
        }

        showToast(`Status updated to "${newStatus}"`, 'success');
        renderFilteredReports(false); // Re-render to update counters and UI
    } catch (err) {
        console.error('[Admin] Single status update error:', err);
        showToast('Failed to update status', 'error');
        renderFilteredReports(false); // Re-render to revert UI if needed
    }
}

async function bulkDelete() {
    if (selectedIds.size === 0) return;
    const count = selectedIds.size;
    const idsToRemove = new Set(selectedIds);
    
    // Optimistic local update
    allReports = allReports.filter(r => !idsToRemove.has(r.docId));
    clearSelection();
    renderFilteredReports(false);

    try {
        const batch = writeBatch(db);
        idsToRemove.forEach(docId => {
            batch.delete(doc(db, 'reports', docId));
        });
        
        await batch.commit();
        showToast(`Deleted ${count} report(s)`, 'success');
    } catch (err) {
        console.error('[Admin] Bulk delete error:', err);
        showToast('Failed to delete reports', 'error');
    }
}

function clearSelection() {
    selectedIds.clear();
    updateToolbarState();
    // Uncheck all visible checkboxes
    document.querySelectorAll('.report-row-checkbox').forEach(cb => cb.checked = false);
    const selectAll = document.getElementById('select-all-checkbox');
    if (selectAll) selectAll.checked = false;
}

function updateToolbarState() {
    const countBadge = document.getElementById('selected-count-badge');
    const deleteBtn = document.getElementById('delete-selected-btn');
    const statusBtn = document.getElementById('bulk-status-btn');

    if (countBadge) {
        countBadge.textContent = selectedIds.size > 0 ? `${selectedIds.size} selected` : '';
        countBadge.classList.toggle('hidden', selectedIds.size === 0);
    }

    const hasSelection = selectedIds.size > 0;
    if (deleteBtn) deleteBtn.disabled = !hasSelection;
    if (statusBtn) statusBtn.disabled = !hasSelection;
}

// ---------- Checkbox Logic ----------
function handleSelectAll(checked) {
    const checkboxes = document.querySelectorAll('.report-row-checkbox');
    checkboxes.forEach(cb => {
        cb.checked = checked;
        const docId = cb.dataset.docId;
        if (docId) {
            if (checked) selectedIds.add(docId);
            else selectedIds.delete(docId);
        }
    });
    updateToolbarState();
}

function handleRowCheckbox(cb) {
    const docId = cb.dataset.docId;
    if (!docId) return;
    if (cb.checked) selectedIds.add(docId);
    else selectedIds.delete(docId);

    // Update select-all state
    const allBoxes = document.querySelectorAll('.report-row-checkbox');
    const selectAll = document.getElementById('select-all-checkbox');
    if (selectAll && allBoxes.length > 0) {
        selectAll.checked = [...allBoxes].every(b => b.checked);
        selectAll.indeterminate = !selectAll.checked && [...allBoxes].some(b => b.checked);
    }
    updateToolbarState();
}

// ---------- Sorting Logic ----------
function sortReportsArray(reports, column, direction) {
    reports.sort((a, b) => {
        let valA = a[column];
        let valB = b[column];

        if (column === 'id') {
            valA = Number(valA) || 0;
            valB = Number(valB) || 0;
        } else if (column === 'date') {
            const dateA = parseReportDate(valA);
            const dateB = parseReportDate(valB);
            valA = dateA ? dateA.getTime() : 0;
            valB = dateB ? dateB.getTime() : 0;
        } else {
            if (column === 'location') {
                valA = a.address || '';
                valB = b.address || '';
            }
            valA = String(valA || '').toLowerCase();
            valB = String(valB || '').toLowerCase();
        }

        if (valA < valB) return direction === 'asc' ? -1 : 1;
        if (valA > valB) return direction === 'asc' ? 1 : -1;
        return 0;
    });
}

// ---------- Render ----------
export function renderFilteredReports(resetPage = true) {
    const filtered = applyFilters(allReports);

    // Sort before paginating
    sortReportsArray(filtered, currentSortColumn, currentSortDirection);

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
            // Build colgroup — admin gets extra checkbox column
            const adminCol = _isAdmin ? `<col style="width: 4%">` : '';
            const adminTh = _isAdmin
                ? `<th class="report-cell-checkbox"><input type="checkbox" id="select-all-checkbox" class="admin-checkbox" title="Select all"></th>`
                : '';

            const th = (colId, label) => {
                const isActive = currentSortColumn === colId;
                const icon = isActive ? (currentSortDirection === 'asc' ? '↑' : '↓') : '↕';
                const activeClass = isActive ? 'sort-active' : '';
                return `<th class="sortable-header ${activeClass}" data-sort="${colId}">${label} <span class="sort-icon">${icon}</span></th>`;
            };

            reportsList.innerHTML = `
                <div class="w-full overflow-x-auto">
                    <table class="reports-table">
                        <colgroup>
                            ${adminCol}
                            <col style="width: ${_isAdmin ? '13%' : '14%'}">
                            <col style="width: 12%">
                            <col style="width: ${_isAdmin ? '22%' : '25%'}">
                            <col style="width: 15%">
                            <col style="width: 8%">
                            <col style="width: 12%">
                            <col style="width: 14%">
                        </colgroup>
                        <thead>
                            <tr class="reports-table-header">
                                ${adminTh}
                                ${th('id', 'ID')}
                                ${th('hazardType', 'Hazard Type')}
                                ${th('location', 'Location')}
                                ${th('date', 'Date')}
                                <th class="text-center">Image</th>
                                ${th('status', 'Status')}
                                ${th('reportedBy', 'Reported By')}
                            </tr>
                        </thead>
                        <tbody>
                            ${pageReports.map((r) => renderReportRow(r)).join('')}
                        </tbody>
                    </table>
                </div>`;

            // Add click listeners for images (open full-size, not thumbnail)
            document.querySelectorAll('.report-img-clickable').forEach(img => {
                img.addEventListener('click', (e) => {
                    openImageModal(e.target.dataset.fullSrc || e.target.src);
                });
            });

            // Add click listeners for address cells
            document.querySelectorAll('.address-link').forEach(el => {
                el.addEventListener('click', () => {
                    const reportId = el.dataset.reportId;
                    flyToReport(reportId, currentReports);
                });
            });

            // Admin: wire checkboxes
            if (_isAdmin) {
                const selectAllCb = document.getElementById('select-all-checkbox');
                if (selectAllCb) {
                    selectAllCb.addEventListener('change', () => handleSelectAll(selectAllCb.checked));
                    // Restore indeterminate state for already-selected rows on re-render
                }

                document.querySelectorAll('.report-row-checkbox').forEach(cb => {
                    // Restore checked state from selectedIds
                    if (selectedIds.has(cb.dataset.docId)) cb.checked = true;
                    cb.addEventListener('change', () => handleRowCheckbox(cb));
                });

                // Restore select-all state
                const allBoxes = document.querySelectorAll('.report-row-checkbox');
                if (selectAllCb && allBoxes.length > 0) {
                    const checkedCount = [...allBoxes].filter(b => b.checked).length;
                    selectAllCb.checked = checkedCount === allBoxes.length;
                    selectAllCb.indeterminate = checkedCount > 0 && checkedCount < allBoxes.length;
                }

                updateToolbarState();
            }

            // Status change listener (for interactive status badges)
            document.querySelectorAll('.status-select-overlay').forEach(select => {
                select.addEventListener('change', async (e) => {
                    const docId = e.target.dataset.docId;
                    const newStatus = e.target.value;
                    if (docId && newStatus) {
                        // Disable select while updating
                        e.target.disabled = true;
                        e.target.closest('.status-interactive-wrapper').classList.add('updating');
                        await updateSingleReportStatus(docId, newStatus);
                    }
                });
            });
        }
    }

    // Update pagination controls
    updatePaginationControls(filtered.length, totalPages, startIdx, endIdx);

    // Update map markers: show page reports only, unless admin toggled "show all"
    updateMapMarkers(_showAllMarkers ? filtered : pageReports);

    // Update mobile badge
    updateFilterBadge();

    // Update show-all-markers button state
    updateShowAllMarkersButton(filtered.length, pageReports.length);

    // Update reset sort button visibility
    const resetBtn = document.getElementById('reset-sort-btn');
    if (resetBtn) {
        if (currentSortColumn !== 'id' || currentSortDirection !== 'desc') {
            resetBtn.classList.remove('hidden');
        } else {
            resetBtn.classList.add('hidden');
        }
    }
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

    const docId = report.docId || '';
    const adminCheckboxTd = _isAdmin
        ? `<td class="report-cell report-cell-checkbox"><input type="checkbox" class="report-row-checkbox admin-checkbox" data-doc-id="${docId}"></td>`
        : '';

    return `
    <tr class="report-row" data-report-id="${report.id || ''}" data-doc-id="${docId}">
      ${adminCheckboxTd}
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
          data-full-src="${getDisplayImageUrl(report.imageUrl, { thumbnail: false })}"
          alt="Hazard"
          class="report-img report-img-clickable"
          loading="lazy"
        />
      </td>
      <td class="report-cell">
        ${_isAdmin ? `
          <div class="status-interactive-wrapper">
            <select class="status-select-overlay" data-doc-id="${docId}">
              <option value="new" ${report.status === 'new' ? 'selected' : ''}>New</option>
              <option value="in-progress" ${report.status === 'in-progress' ? 'selected' : ''}>In Progress</option>
              <option value="fixed" ${report.status === 'fixed' ? 'selected' : ''}>Fixed</option>
            </select>
            <div class="status-capsule-display">
               <span class="badge ${statusClass}">${report.status || 'new'}</span>
            </div>
          </div>
        ` : `
          <span class="badge ${statusClass}">${report.status || 'new'}</span>
        `}
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
// SORTING
// ============================================

export function setupSorting() {
    const reportsList = document.getElementById('reports-list');
    if (reportsList) {
        reportsList.addEventListener('click', (e) => {
            const th = e.target.closest('.sortable-header');
            if (!th) return;
            const column = th.dataset.sort;
            if (currentSortColumn === column) {
                currentSortDirection = currentSortDirection === 'asc' ? 'desc' : 'asc';
            } else {
                currentSortColumn = column;
                currentSortDirection = (column === 'id' || column === 'date') ? 'desc' : 'asc';
            }
            renderFilteredReports(true);
        });
    }

    const resetBtn = document.getElementById('reset-sort-btn');
    if (resetBtn) {
        resetBtn.addEventListener('click', () => {
            currentSortColumn = 'id';
            currentSortDirection = 'desc';
            renderFilteredReports(true);
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

// ---------- Show All Markers (Admin Only) ----------
export function toggleShowAllMarkers() {
    _showAllMarkers = !_showAllMarkers;
    renderFilteredReports(false); // Re-render to update map markers
}

function updateShowAllMarkersButton(totalFiltered, pageCount) {
    const btn = document.getElementById('show-all-markers-btn');
    if (!btn) return;

    // Only show for admin and only if there are more reports than current page shows
    if (!_isAdmin || totalFiltered <= pageCount) {
        btn.classList.add('hidden');
        return;
    }

    btn.classList.remove('hidden');
    if (_showAllMarkers) {
        btn.classList.add('active');
        btn.innerHTML = `🗺️ Showing All (${totalFiltered})`;
    } else {
        btn.classList.remove('active');
        btn.innerHTML = `🗺️ Show All Markers (${totalFiltered})`;
    }
}
