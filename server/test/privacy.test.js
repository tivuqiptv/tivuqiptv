import test from 'node:test';
import assert from 'node:assert/strict';

import {
  privacyDisclosure,
  renderPrivacyPage,
  resolvePrivacyLanguage,
} from '../src/privacy.js';

const config = {
  privacyControllerName: 'Example Controller',
  privacyContactEmail: 'privacy@example.test',
  privacyEffectiveDate: '2026-08-14',
  auditRetentionDays: 180,
};

const retention = {
  auditDays: 180,
  pairingMetadataDays: 30,
  paymentRawEventDays: 30,
  deletionRequestDays: 365,
  tombstoneDays: 365,
};

test('privacy language follows supported language and falls back to English', () => {
  assert.equal(resolvePrivacyLanguage('de'), 'de');
  assert.equal(resolvePrivacyLanguage('', 'tr-TR,tr;q=0.9'), 'tr');
  assert.equal(resolvePrivacyLanguage('fr'), 'en');
});

test('privacy page includes controller, contact and concrete retention periods', () => {
  const page = renderPrivacyPage({
    language: 'en',
    controllerName: config.privacyControllerName,
    contactEmail: config.privacyContactEmail,
    effectiveDate: config.privacyEffectiveDate,
    retention,
  });
  assert.match(page, /Example Controller/);
  assert.match(page, /privacy@example\.test/);
  assert.match(page, /at most 10 minutes/);
  assert.match(page, /180 days/);
  assert.match(page, /playlist address is erased from the server immediately/);
  assert.match(page, /watch history are stored on the device/);
});

test('Amazon disclosure states what is local and what backend collects', () => {
  const disclosure = privacyDisclosure(config);
  assert.equal(disclosure.sellsPersonalData, false);
  assert.equal(disclosure.behavioralAdvertising, false);
  assert.equal(
    disclosure.data.find((item) => item.category === 'app_activity_watch_history')
      .collectedByBackend,
    false,
  );
  assert.equal(
    disclosure.data.find((item) => item.category === 'user_content_playlist_url')
      .maximumPendingMinutes,
    10,
  );
});
