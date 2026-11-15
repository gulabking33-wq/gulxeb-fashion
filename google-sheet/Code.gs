/**
 * Gulxeb Fashion — save new customer accounts to this Google Sheet.
 *
 * Setup (once):
 * 1. Open the Google Sheet → Extensions → Apps Script. Paste this whole file. Save.
 * 2. Put your Firebase Web API key in FIREBASE_API_KEY below (same as in index.html).
 * 3. Deploy → New deployment → type "Web app" → Execute as: Me → Who has access: Anyone → Deploy.
 * 4. Copy the Web app URL into CONFIG.sheetUrl in index.html.
 */
const FIREBASE_API_KEY = '';           // e.g. 'AIzaSy...'
const SHEET_NAME = 'Customers';
const HEADERS = ['Created (IST)', 'Name', 'Mobile', 'Email', 'OTP verified', 'Device', 'Last seen (IST)', 'Sign-ins'];

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const data = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    if (data.type !== 'signup') return out({ ok: false });

    const name  = clean(data.name, 80);
    const email = clean(data.email, 120);
    let phone   = clean(data.phone, 20).replace(/[^\d+]/g, '');
    if (!name || !/^\+91[6-9]\d{9}$/.test(phone)) return out({ ok: false, error: 'invalid' });

    // Confirm the OTP really verified this number (stops fake entries)
    let verified = 'No';
    if (FIREBASE_API_KEY && data.idToken) {
      const r = UrlFetchApp.fetch('https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=' + FIREBASE_API_KEY, {
        method: 'post', contentType: 'application/json', muteHttpExceptions: true,
        payload: JSON.stringify({ idToken: data.idToken })
      });
      const u = JSON.parse(r.getContentText() || '{}');
      const fbPhone = u.users && u.users[0] && u.users[0].phoneNumber;
      if (fbPhone && fbPhone === phone) verified = 'Yes';
      else return out({ ok: false, error: 'not verified' });
    } else if (FIREBASE_API_KEY) {
      return out({ ok: false, error: 'not verified' });
    }

    const sh = sheet();
    const now = Utilities.formatDate(new Date(), 'Asia/Kolkata', 'dd-MM-yyyy HH:mm');
    const device = /Mobile|Android|iPhone/i.test(data.userAgent || '') ? 'Mobile' : 'Desktop';
    const phones = sh.getLastRow() > 1 ? sh.getRange(2, 3, sh.getLastRow() - 1, 1).getValues().map(r => String(r[0])) : [];
    const idx = phones.indexOf(phone);
    if (idx > -1) {
      const row = idx + 2;
      sh.getRange(row, 2).setValue(name);
      if (email) sh.getRange(row, 4).setValue(email);
      if (verified === 'Yes') sh.getRange(row, 5).setValue('Yes');
      sh.getRange(row, 7).setValue(now);
      sh.getRange(row, 8).setValue((Number(sh.getRange(row, 8).getValue()) || 1) + 1);
    } else {
      sh.appendRow([now, name, phone, email, verified, device, now, 1]);
    }
    return out({ ok: true });
  } catch (err) {
    return out({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function doGet() { return out({ ok: true, service: 'gulxeb-customers' }); }

function sheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(SHEET_NAME);
  if (!sh) sh = ss.insertSheet(SHEET_NAME);
  if (sh.getLastRow() === 0) {
    sh.appendRow(HEADERS);
    sh.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold').setBackground('#171513').setFontColor('#ffffff');
    sh.setFrozenRows(1);
    sh.getRange('C:C').setNumberFormat('@');
  }
  return sh;
}
function clean(v, max) {
  let s = String(v == null ? '' : v).trim().slice(0, max);
  if (/^[=+\-@]/.test(s) && !/^\+91\d{10}$/.test(s)) s = "'" + s;   // block formula injection
  return s;
}
function out(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }
