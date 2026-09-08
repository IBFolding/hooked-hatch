import fs from 'node:fs';
const text = fs.readFileSync(new URL('../web/config.js', import.meta.url), 'utf8');
const required = [
  '4663',
  '0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC'
];
for (const value of required) {
  if (!text.includes(value)) throw new Error(`Missing required config value: ${value}`);
}
console.log('HOOKED config sanity check passed.');
