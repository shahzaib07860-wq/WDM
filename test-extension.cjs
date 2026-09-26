'use strict';
const vm = require('node:vm');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {setTimeout: wait} = require('node:timers/promises');
const hooks = {}, calls = [], state = {}, actions = [];
const event = name => ({addListener: fn => hooks[name] = fn});
const chrome = {
  runtime: {onMessage: event('message'), onInstalled: event('installed')},
  storage: {session: {get: async key => ({[key]: state[key]}), set: async x => Object.assign(state, x), remove: async key => {delete state[key];}}, local: {get: async defaults => defaults, set: async () => {}}},
  action: {setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}},
  cookies: {getAll: async () => []}, notifications: {create: async () => {}},
  contextMenus: {removeAll: async () => {}, create: () => {}, onClicked: event('clicked')},
  webRequest: {onBeforeSendHeaders: event('headers'), onResponseStarted: event('response'), onErrorOccurred: event('error')},
  tabs: {onUpdated: event('updated'), onRemoved: event('removed')},
  downloads: {onCreated: event('download'), pause: async () => actions.push('pause'), cancel: async () => actions.push('cancel'), erase: async () => {}, resume: async () => actions.push('resume')},
};
let rejectSend = false;
const fetch = async (url, opts) => {
  calls.push({url, opts});
  if (url.endsWith('/wdm-health')) return {ok: true, json: async () => ({app: 'WDM 2'})};
  return {ok: true, json: async () => rejectSend ? {captured: false} : {captured: true, accepted: true}};
};
const ctx = vm.createContext({chrome, navigator: {userAgent: 'test', language: 'en'}, URL, AbortSignal, Map, Promise, console, fetch});
vm.runInContext(fs.readFileSync('extension/background.js', 'utf8'), ctx);
const message = (msg, sender = {tab: {id: 7, url: 'https://example.test/page'}}) => new Promise(resolve => hooks.message(msg, sender, resolve));
(async () => {
  assert.equal((await message({type: 'health'})).ok, true);
  hooks.headers({tabId: 7, requestId: 'one', requestHeaders: [{name: 'Authorization', value: 'Bearer fixture'}]});
  hooks.response({tabId: 7, requestId: 'one', url: 'https://example.test/playlist', statusCode: 200, responseHeaders: [{name: 'Content-Type', value: 'application/vnd.apple.mpegurl'}]});
  await wait(5);
  const media = await message({type: 'get-media'});
  assert.equal(media.items[0].type, 'HLS');
  assert.equal(media.items[0].headers, undefined);
  assert.equal((await message({type: 'send', url: media.items[0].url})).ok, true);
  let body = JSON.parse(calls.at(-1).opts.body);
  assert.equal(body.type, 'm3u8'); assert.equal(body.extensionVersion, '2.0.1'); assert.equal(body.tabId, 7);
  await message({type: 'send', url: 'https://example.test/file.zip'});
  body = JSON.parse(calls.at(-1).opts.body);
  assert.equal(body.type, 'single'); assert.equal(body.data.referer, 'https://example.test/page');
  assert.equal((await message({type: 'send', url: 'blob:https://example.test/123'})).ok, false);
  rejectSend = true;
  await hooks.download({id: 12, url: 'https://example.test/new.zip', referrer: 'https://example.test/page'});
  assert.deepEqual(actions, ['pause', 'resume']);
  assert.equal((await message({type: 'open'})).ok, false);
  const manifest = JSON.parse(fs.readFileSync('extension/manifest.json'));
  assert(manifest.host_permissions.includes('http://127.0.0.1/*'));
  assert(manifest.host_permissions.includes('http://localhost/*'));
  assert.equal(manifest.version, '2.0.1');
  console.log('PASS: health, HLS detection, file message, blob guidance, browser fallback, extension port');
})().catch(error => {console.error(error); process.exitCode = 1;});
