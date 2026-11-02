// ext 为 null（瓜子 | 流畅），用内置域名
// App 里 rsaX 由原生 JSCrypto 提供，这里用 Node crypto 模拟（RSA/PKCS1，公钥加密 / 私钥解密）
import crypto from 'node:crypto';
globalThis.rsaX ??= (mode, pub, enc, input, inB64, key, outB64) => {
  const data = inB64 ? Buffer.from(input, 'base64') : Buffer.from(input);
  const o = { key, padding: crypto.constants.RSA_PKCS1_PADDING };
  const out = pub && enc ? crypto.publicEncrypt(o, data) : crypto.privateDecrypt(o, data);
  return outB64 ? out.toString('base64') : out.toString('utf8');
};
export const ext = '';
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length === 5 && h.filters['1'].length === 4, 'home');
  const c = await s.category('2', '1', true, {});
  assert.ok(c.list.length && c.list[0].vod_id, 'category');
  assert.ok((await s.homeVod()).list.length, 'homeVod');
  const d = (await s.detail(c.list[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url.includes('$'), 'detail');
  assert.ok((await s.search(d.vod_name.slice(0, 2), false, '1')).list.length, 'search');
  const p = await s.play(d.vod_play_from, d.vod_play_url.split('#')[0].split('$')[1], []);
  assert.ok(/^https?:/.test(p.url), 'play');
  return `${d.vod_name} (${d.vod_play_url.split('#').length} eps) -> ${p.url.slice(0, 70)}`;
};
