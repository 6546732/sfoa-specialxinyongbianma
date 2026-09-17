// Exercise async component state without a browser or Salesforce connection.
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = readFileSync(resolve(__dirname, '../force-app/main/default/lwc/sccCreditCodeAction/sccCreditCodeAction.js'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '')
  .replace(/^\s*@api\s*$/gm, '')
  .replace('export default class', 'class');
function component(overrides) {
  const scope = { LightningElement: class {}, ...overrides };
  vm.createContext(scope);
  const Action = vm.runInContext(source + '\nSccCreditCodeAction;', scope);
  const action = new Action();
  action.toast = () => {};
  return action;
}
(async () => {
  let complete;
  const action = component({ preview: () => new Promise(resolve => { complete = resolve; }) });
  action.manualBody = 'SHK30653538';
  action.manualPreview = { finalCode: 'stale' };
  const pending = action.handlePreview();
  assert.equal(action.manualPreview, null);
  action.manualBody = 'changed';
  complete({ finalCode: 'SHK306535389' });
  await pending;
  assert.equal(action.manualPreview, null, 'late preview must not replace current input');

  const failed = component({ preview: async () => { throw new Error('invalid'); } });
  failed.manualPreview = { finalCode: 'stale' };
  await failed.handlePreview();
  assert.equal(failed.manualPreview, null);

  const lookup = component({ research: async () => { throw new Error('offline'); }, findSimilarCustomers: async () => [] });
  lookup.researchResult = { auditId: 'stale' };
  await lookup.handleResearch();
  assert.equal(lookup.researchResult, null, 'failed retry must not leave old research usable');
  assert.equal(lookup.busy, false);
  assert.equal(lookup.researching, false);
  let calls = 0;
  const success = component({
    research: async () => { calls++; return { sources: [{name: '登记网站', url: 'https://registry.example.test/company'}] }; },
    findSimilarCustomers: () => { throw new Error('similar search must never run'); },
    notifyRecordUpdateAvailable: async () => {}
  });
  success.refreshAccount = async () => {};
  await success.handleResearch();
  assert.equal(calls, 1);
  assert.equal(success.sources[0].domain, 'registry.example.test');
  assert.equal(success.hasSources, true);
  assert.equal(success.researching, false);
  console.log('PASS: 4 UI state regressions, single lookup and visible source domain');
})().catch(error => { console.error(error); process.exitCode = 1; });
