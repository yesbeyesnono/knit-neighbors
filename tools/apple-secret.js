// Sign in with Apple 용 client_secret(JWT) 생성기 — Supabase Apple 제공자 "Secret Key"에 붙여넣는 값
// 사용법:  node tools/apple-secret.js <AuthKey_XXXX.p8 경로>
// 비밀키(.p8)는 이 PC 밖으로 보내지 마세요. 생성된 secret은 6개월 뒤 만료되므로 그때 다시 실행합니다.
const fs = require('fs');
const crypto = require('crypto');

const TEAM_ID = 'M59979ZT3A';                        // Apple Developer 팀 ID (FIRMTECH INC.)
const KEY_ID = '8RR6P598B2';                          // Keys 에서 만든 Sign in with Apple 키 ID
const CLIENT_ID = 'kr.co.firmtech.knitneighbors.web'; // Services ID (웹·Supabase 로그인용)

const p8Path = process.argv[2];
if (!p8Path || !fs.existsSync(p8Path)) { console.error('사용법: node tools/apple-secret.js <AuthKey_XXXX.p8 경로>'); process.exit(1); }
const privateKey = fs.readFileSync(p8Path, 'utf8');

const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' };
const payload = { iss: TEAM_ID, iat: now, exp: now + 60 * 60 * 24 * 180, aud: 'https://appleid.apple.com', sub: CLIENT_ID }; // 180일
const signingInput = `${b64(header)}.${b64(payload)}`;
const signature = crypto.sign('sha256', Buffer.from(signingInput), { key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
const jwt = `${signingInput}.${signature}`;

console.log('\n=== Supabase > Authentication > Providers > Apple ===');
console.log('Client IDs :', CLIENT_ID);
console.log('Secret Key :\n' + jwt);
console.log('\n만료일     :', new Date((now + 60 * 60 * 24 * 180) * 1000).toLocaleDateString('ko-KR'), '(이날 전에 다시 생성)');
