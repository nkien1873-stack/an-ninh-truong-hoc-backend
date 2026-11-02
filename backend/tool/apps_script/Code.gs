// Dán file này vào script.google.com. Backend gọi doPost qua HTTPS để gửi mã OTP bằng Gmail
// của chủ script, thay cho SMTP (Render miễn phí chặn các cổng SMTP của Gmail).

// Phải trùng biến MAIL_SCRIPT_SECRET của backend.
const SECRET = '__MAIL_SCRIPT_SECRET__';

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    if (body.secret !== SECRET) return reply({ ok: false, error: 'unauthorized' });
    MailApp.sendEmail({
      to: body.to,
      subject: body.subject,
      body: body.text,
      htmlBody: body.html,
      name: body.fromName,
    });
    return reply({ ok: true, remaining: MailApp.getRemainingDailyQuota() });
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  }
}

function reply(data) {
  return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(ContentService.MimeType.JSON);
}

// Bấm Run hàm này một lần để cấp quyền gửi mail và thử gửi tới chính bạn.
function guiThu() {
  MailApp.sendEmail(Session.getEffectiveUser().getEmail(), 'Thử gửi OTP', 'Apps Script gửi mail được.');
}
