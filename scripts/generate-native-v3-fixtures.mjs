import { createHash, createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pins = JSON.parse(await readFile(join(root, 'NATIVE-PINS.json')));
const args = process.argv.slice(2);
let sourceCheckout;
let check = false;
for (let index = 0; index < args.length; index++) {
  const argument = args[index];
  if (argument === '--check' && !check) { check = true; }
  else if (argument === '--ios-source' && sourceCheckout === undefined && args[index + 1] && !args[index + 1].startsWith('--')) { sourceCheckout = args[++index]; }
  else { throw new Error('Use --ios-source <checkout> and/or --check once each'); }
}
const native = resolve(sourceCheckout ?? join(root, '.native/ios'));
const revision = execFileSync('git', ['-C', native, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (revision !== pins.ios.revision) throw new Error('The source checkout must match NATIVE-PINS.json');
const source = 'fixtures/journeys/planes/release.json';
const sourceBytes = execFileSync('git', ['-C', native, 'show', revision + ':' + source]);
const outputRoot = join(root, 'ios-plugin/Tests/NuxieGodotBridgeTests/native-v3');
await mkdir(outputRoot, { recursive: true });
async function save(name, bytes) {
  const path = join(outputRoot, name);
  if (check) {
    if (!Buffer.from(await readFile(path)).equals(Buffer.from(bytes))) throw new Error('Fixture differs: ' + name);
  } else { await writeFile(path, bytes); }
}
const golden = JSON.parse(sourceBytes);
const descriptor = JSON.parse(Buffer.from(golden.entry.envelope.descriptorBytesBase64, 'base64'));
const key = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), Buffer.alloc(32, 0x42)]), format: 'der', type: 'pkcs8' });
const publicKey = createPublicKey(key);
const sha = data => createHash('sha256').update(data).digest('hex');
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value) : Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']' : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';

descriptor.identity = { appId: 'app_wrapper_v3', buildId: 'build_wrapper_v3', environment: 'test', experienceId: 'experience_wrapper_v3', experienceVersionId: 'version_wrapper_v3', publishedAt: '2026-10-11T12:00:00.000Z', publishedAtSeq: 4288, versionNumber: 3 };
descriptor.leg.entryCondition = { type: 'event', eventName: 'wrapper_v3_probe' };
descriptor.leg.policy.entry.trigger = { type: 'event', eventName: 'wrapper_v3_probe' };
const fields = [{ key: 'probeNumber', type: 'number', required: true }, { key: 'probeText', type: 'string', required: true }, { key: 'probeBoolean', type: 'boolean', required: true }];
descriptor.leg.inputs = { eventFields: fields, responseFields: [] };
descriptor.leg.completionOutputs = { continue: { eventFields: fields, responseFields: [] } };
descriptor.metadata.name = 'Downstream native v3 admission and typed event values';
descriptor.metadata.description = 'Screenless native Journey fixture for actual downstream adapter consumers';

const cases = [
  { name: 'accepted', schema: 'nuxie.journey-release.v3', signatureDomain: 'nuxie.journey-release.v3\0', verdict: 'accepted', reason: null },
  { name: 'retired-v1', schema: 'nuxie.journey-release.v1', signatureDomain: 'nuxie.journey-release.v3\0', verdict: 'rejected', reason: 'journey_release.descriptor.invalid' },
  { name: 'retired-v2', schema: 'nuxie.journey-release.v2', signatureDomain: 'nuxie.journey-release.v3\0', verdict: 'rejected', reason: 'journey_release.descriptor.invalid' },
  { name: 'wrong-domain', schema: 'nuxie.journey-release.v3', signatureDomain: 'nuxie.journey-release.v2\0', verdict: 'rejected', reason: 'journey_release.signature.bad_signature' },
];
const manifest = { nativeIOSRevision: pins.ios.revision, nativeAndroidRevision: pins.android.revision, sourceRepository: pins.ios.repository, source, sourceSha256: sha(sourceBytes), publicKeyBase64: golden.publicKeyBase64, trigger: 'wrapper_v3_probe', triggerProperties: { probeNumber: 42, probeText: 'native-v3-wrapper', probeBoolean: true }, authorityHeaders: { 'Nuxie-App-Id': descriptor.identity.appId, 'Nuxie-App-Environment': 'test' }, expectedActivities: ['journey_started', 'journey_completed'], expectedProperties: { experience_id: descriptor.identity.experienceId, experience_version: descriptor.identity.experienceVersionId, leg_id: descriptor.leg.id, leg_generation: 0, outcome: 'continue' }, expectedOutputs: { event: { probeNumber: 42, probeText: 'native-v3-wrapper', probeBoolean: true }, responses: {} }, cases: [] };
for (const item of cases) {
  const changed = structuredClone(descriptor); changed.schemaVersion = item.schema;
  const bytes = Buffer.from(canonical(changed));
  const signature = sign(null, Buffer.concat([Buffer.from(item.signatureDomain), bytes]), key);
  const digest = sha(bytes);
  const entry = { locator: { ...descriptor.identity, legId: descriptor.leg.id }, envelope: { mediaType: 'application/vnd.nuxie.journey+json', encoding: 'base64', descriptorSha256: digest, descriptorSizeBytes: bytes.length, descriptorBytesBase64: bytes.toString('base64'), signature: { version: 1, algorithm: 'ed25519', keyId: 'TEST_ONLY_DEV_KEYPAIR', signatureBase64: signature.toString('base64') } } };
  const profile = { schemaVersion: 'nuxie.journey-plane-profile.v2', status: 'ok', delivery: { renderBaseUrl: 'https://wrapper-v3.nuxie.test/', assetBaseUrl: 'https://wrapper-v3.nuxie.test/' }, features: [], facts: { properties: {}, memberships: {}, assignments: {} }, releases: [entry], armedLegs: [{ reference: { experienceId: descriptor.identity.experienceId, versionId: descriptor.identity.experienceVersionId, legId: descriptor.leg.id, descriptorSha256: digest }, binding: { type: 'new' }, entryCondition: descriptor.leg.entryCondition, context: { event: {}, responses: {} } }] };
  const output = Buffer.from(JSON.stringify(profile, null, 2) + '\n');
  await save(item.name + '.json', output);
  manifest.cases.push({ ...item, file: item.name + '.json', sha256: sha(output), descriptorSha256: digest, validUnderDeclaredDomain: verify(null, Buffer.concat([Buffer.from(item.signatureDomain), bytes]), publicKey, signature), validUnderV3Domain: verify(null, Buffer.concat([Buffer.from('nuxie.journey-release.v3\0'), bytes]), publicKey, signature) });
}
await save('manifest.json', JSON.stringify(manifest, null, 2) + '\n');
console.log('Native v3 fixtures ' + (check ? 'match' : 'generated') + ' ' + revision);
