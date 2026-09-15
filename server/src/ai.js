import Anthropic from '@anthropic-ai/sdk';
import { log, CATEGORY_SLUGS } from './util.js';

// AI provayder: GEMINI_API_KEY berilsa Google Gemini, aks holda ANTHROPIC_API_KEY bo'lsa Claude ishlatiladi.
const GEMINI_KEY = process.env.GEMINI_API_KEY || '';
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-3.6-flash';
// Asosiy model band (503) yoki limit tugagan (429) bo'lsa, shu model bilan yana bir marta urinib ko'riladi
const GEMINI_FALLBACK = process.env.GEMINI_FALLBACK_MODEL ?? 'gemini-3.5-flash';
const CLAUDE_MODEL = process.env.AI_MODEL || 'claude-opus-5';

const provider = GEMINI_KEY ? 'gemini' : process.env.ANTHROPIC_API_KEY ? 'anthropic' : null;
export const aiEnabled = () => provider !== null;
export const aiInfo = { provider, model: provider === 'gemini' ? GEMINI_MODEL : provider === 'anthropic' ? CLAUDE_MODEL : null };
const client = provider === 'anthropic' ? new Anthropic() : null;

/** Ilova chat pufakchalari oddiy matn ko'rsatadi: markdown belgilarini olib tashlaymiz */
export function plainText(t) {
  return t
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/__(.+?)__/g, '$1')
    .replace(/^\s{0,3}#{1,6}\s+/gm, '')
    .replace(/^(\s*)[*-]\s+/gm, '$1• ')
    .replace(/(^|[^*\w])\*(?!\s)([^*\n]+?)\*(?![*\w])/g, '$1$2')
    .replace(/`([^`\n]+)`/g, '$1');
}

const NO_AI = "AI yordamchi hozircha o'chirilgan (serverda GEMINI_API_KEY sozlanmagan). Do'konlar va mahsulotlarni katalogdan qidiring.";
const REFUSED = "Bu so'rovga javob bera olmayman.";

/** Tarix + yangi xabar: ketma-ket bir xil rollar birlashtiriladi, birinchisi user bo'lishi shart */
function toTurns(history, user) {
  const turns = [];
  const all = [...history.filter((m) => m.text).map((m) => ({ role: m.role === 'assistant' ? 'assistant' : 'user', text: m.text })), { role: 'user', text: user }];
  for (const m of all) {
    const last = turns[turns.length - 1];
    if (last && last.role === m.role) last.text += `\n\n${m.text}`;
    else turns.push({ ...m });
  }
  while (turns.length && turns[0].role !== 'user') turns.shift();
  return turns;
}

// ---------- Google Gemini ----------
class GeminiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function geminiGenerate(model, body) {
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_KEY },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60_000),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new GeminiError(r.status, data?.error?.message || `HTTP ${r.status}`);
  return data;
}

async function askGemini({ system, turns, effort, maxTokens, json }) {
  const bodyFor = (model) => {
    const thinking = /^gemini-3/.test(model);
    return {
      systemInstruction: { parts: [{ text: system }] },
      contents: turns.map((t) => ({ role: t.role === 'assistant' ? 'model' : 'user', parts: [{ text: t.text }] })),
      generationConfig: {
        // Fikrlash tokenlari uchun ham joy qoldiriladi
        maxOutputTokens: maxTokens + 2048,
        ...(json ? { responseMimeType: 'application/json' } : {}),
        ...(thinking ? { thinkingConfig: { thinkingLevel: effort } } : {}),
      },
    };
  };
  let data;
  try {
    data = await geminiGenerate(GEMINI_MODEL, bodyFor(GEMINI_MODEL));
  } catch (e) {
    if (!(e instanceof GeminiError) || ![429, 500, 503].includes(e.status) || !GEMINI_FALLBACK || GEMINI_FALLBACK === GEMINI_MODEL) throw e;
    log('AI', `${GEMINI_MODEL}: ${e.status}, zaxira model ishlatiladi: ${GEMINI_FALLBACK}`);
    data = await geminiGenerate(GEMINI_FALLBACK, bodyFor(GEMINI_FALLBACK));
  }
  if (data.promptFeedback?.blockReason) return REFUSED;
  const c = data.candidates?.[0];
  if (!c) return REFUSED;
  const text = (c.content?.parts || []).filter((p) => p.text && !p.thought).map((p) => p.text).join('').trim();
  if (!text && ['SAFETY', 'PROHIBITED_CONTENT', 'BLOCKLIST', 'SPII', 'RECITATION'].includes(c.finishReason)) return REFUSED;
  return text || '...';
}

// ---------- Anthropic Claude ----------
async function askClaude({ system, turns, effort, maxTokens }) {
  const res = await client.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: maxTokens,
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    output_config: { effort },
    messages: turns.map((t) => ({ role: t.role, content: t.text })),
  });
  if (res.stop_reason === 'refusal') return REFUSED;
  return res.content.filter((b) => b.type === 'text').map((b) => b.text).join('').trim() || '...';
}

async function ask({ system, history = [], user, effort = 'low', maxTokens = 2000, json = false }) {
  if (!provider) return NO_AI;
  const turns = toTurns(history, user);
  try {
    const text = provider === 'gemini'
      ? await askGemini({ system, turns, effort, maxTokens, json })
      : await askClaude({ system, turns, effort, maxTokens });
    return json ? text : plainText(text);
  } catch (e) {
    const status = e?.status;
    log('AI xato', provider, status, e?.message);
    if ((status === 400 && /api key/i.test(e?.message || '')) || status === 401 || status === 403) {
      return `AI kaliti noto'g'ri (${provider === 'gemini' ? 'GEMINI_API_KEY' : 'ANTHROPIC_API_KEY'}).`;
    }
    if (status === 429 || status === 503 || status === 529) return 'AI hozir band, birozdan keyin urinib ko\'ring.';
    return 'AI javob bera olmadi, keyinroq urinib ko\'ring.';
  }
}

const money = (n) => Number(n).toLocaleString('ru-RU').replace(/,/g, ' ');

/** Umumiy xaridor yordamchisi: butun katalog bo'yicha */
export async function assistantReply({ message, history, shops, products, userLoc }) {
  const catalog = shops.map((s) => {
    const ps = products.filter((p) => p.shopId === s.id).slice(0, 40).map((p) => `  - [${p.id}] ${p.name} — ${money(p.price)} so'm${p.category ? ` (${p.category})` : ''}`).join('\n');
    const dist = s.distanceKm != null ? `, ${s.distanceKm} km` : '';
    return `Do'kon [${s.id}] ${s.name} (tel: ${s.phone}${s.address ? `, ${s.address}` : ''}${dist}, sotuvlar: ${s.sales}, daraja: ${s.level})\n${ps || '  (mahsulot yo\'q)'}`;
  }).join('\n\n');
  const system = `Sen Saler AI — O'zbekistondagi mahalliy do'konlar bozorining xarid yordamchisisan. Foydalanuvchi bilan o'zbek tilida (lotin), qisqa va aniq gaplash. Faqat quyidagi katalogdagi do'kon va mahsulotlarni tavsiya qil, o'ylab topma. Narxlarni so'mda yoz. Foydalanuvchi joylashuvi ma'lum bo'lsa yaqinroq do'konlarni afzal ko'r. Mos mahsulot topilmasa, buni ochiq ayt va nima qidirish mumkinligini taklif qil. Javobni oddiy matnda yoz: markdown belgilari (** va #) ishlatma, ro'yxat kerak bo'lsa • belgisidan foydalan.

KATALOG:
${catalog || "(hozircha do'konlar yo'q)"}`;
  const user = userLoc ? `${message}\n\n(Foydalanuvchi joylashuvi: ${userLoc.lat}, ${userLoc.lon})` : message;
  return ask({ system, history, user });
}

/** Do'kon sotuvchisi nomidan chat (AI sotuvchi) */
export async function shopChatReply({ message, history, shop, products }) {
  const ps = products.map((p) => `- [${p.id}] ${p.name} — ${money(p.price)} so'm${p.description ? `. ${p.description.slice(0, 200)}` : ''}`).join('\n');
  const system = `Sen "${shop.name}" do'konining onlayn sotuvchisisan, isming ${shop.sellerName || 'Madina'}. O'zingni shu ism bilan tanishtir. O'zbek tilida (lotin), do'stona va qisqa javob ber. Faqat shu do'kon mahsulotlari haqida gapir, narxlarni aniq ayt, mavjud bo'lmagan narsani va'da qilma. Javobni oddiy matnda yoz: markdown belgilari (** va #) ishlatma, ro'yxat kerak bo'lsa • belgisidan foydalan. Xaridor buyurtma bermoqchi bo'lsa, ilovadagi "Buyurtma berish" tugmasini bosishni ayt. Do'kon telefoni: ${shop.phone || 'ko\'rsatilmagan'}.${shop.description ? ` Do'kon haqida: ${shop.description}` : ''}

MAHSULOTLAR:
${ps || '(mahsulot yo\'q)'}`;
  return ask({ system, history, user: message });
}

/** Sotuvchi uchun maslahatlar: [{type,title,text}] */
export async function sellerAdvice({ shop, stats }) {
  const fallback = [
    { type: 'idea', title: 'Mahsulot rasmlari', text: "Har bir mahsulotga kamida 3 ta sifatli rasm qo'shing — rasmli mahsulotlar ko'proq ko'riladi." },
    { type: 'warning', title: 'Yangi buyurtmalar', text: "Yangi buyurtmalarga 1 soat ichida javob bering, kechikish bekor qilinishga olib keladi." },
    { type: 'idea', title: 'Joylashuv', text: "Do'kon joylashuvini xaritada belgilang — xaridorlar yaqin do'konlarni tanlaydi." },
  ];
  if (!aiEnabled()) return fallback;
  const system = `Sen kichik do'konlar uchun savdo maslahatchisisan. Berilgan statistikaga qarab 3–5 ta aniq, amaliy maslahat ber. FAQAT JSON massiv qaytar, boshqa matn yozma. Har bir element: {"type": "idea" | "warning" | "success", "title": "qisqa sarlavha", "text": "1–2 gap, o'zbek tilida (lotin)"}.`;
  const user = `Do'kon: ${shop.name}\nStatistika (JSON): ${JSON.stringify(stats)}`;
  const raw = await ask({ system, user, maxTokens: 1500, json: true });
  return parseTips(raw, fallback);
}

/** AI javobidagi JSON massivdan maslahatlar: [{type,title,text}], xato bo'lsa zaxira ro'yxat */
function parseTips(raw, fallback) {
  try {
    const m = raw.match(/\[[\s\S]*\]/);
    const arr = JSON.parse(m ? m[0] : raw);
    const tips = arr
      .filter((t) => t && t.title && t.text)
      .map((t) => ({ type: ['idea', 'warning', 'success'].includes(t.type) ? t.type : 'idea', title: String(t.title), text: String(t.text) }));
    return tips.length ? tips.slice(0, 6) : fallback;
  } catch {
    return fallback;
  }
}

const TIP_FORMAT = `FAQAT JSON massiv qaytar, boshqa matn yozma. Har bir element: {"type": "idea" | "warning" | "success", "title": "qisqa sarlavha", "text": "1–2 gap, o'zbek tilida (lotin)"}.`;

/** Kuryer va yuk tashuvchi uchun AI maslahatlar (statistika va bozor ma'lumoti asosida) */
export async function courierInsights({ courier, stats }) {
  const isCargo = courier.type === 'cargo';
  const fallback = isCargo ? cargoFallback(stats) : courierFallback(stats);
  if (!aiEnabled()) return fallback;
  const system = isCargo
    ? `Sen O'zbekistondagi viloyatlararo yuk tashuvchilar uchun biznes maslahatchisisan. Statistika, bozor narxlari va talab yuqori yo'nalishlarga qarab 3–5 ta aniq, amaliy maslahat ber: narxni bozor bilan solishtir (raqamlarni so'mda ayt), qaysi yo'nalishga e'tibor berish, so'rovlarni qabul qilish ulushi, profilni yaxshilash. Ma'lumotda yo'q narsani o'ylab topma. ${TIP_FORMAT}`
    : `Sen O'zbekistondagi shahar ichi kuryerlari uchun daromad maslahatchisisan. Statistika (yetkazishlar, daromad, km, faol soatlar, buyurtma ko'p do'konlar, kutayotgan buyurtmalar) asosida 3–5 ta aniq, amaliy maslahat ber: qaysi soatlarda onlayn bo'lish, qaysi hududda turish, tarifni qanday belgilash, rad etishlarni kamaytirish. Raqamlarni keltir, ma'lumotda yo'q narsani o'ylab topma. ${TIP_FORMAT}`;
  const user = `${isCargo ? 'Yuk tashuvchi' : 'Kuryer'}: ${courier.name}; transport: ${courier.vehicleType || courier.vehicle}; viloyatlar: ${(courier.regions || []).join(', ') || '-'}\nStatistika (JSON): ${JSON.stringify(stats)}`;
  return parseTips(await ask({ system, user, maxTokens: 1500, json: true }), fallback);
}

function courierFallback(s) {
  const tips = [];
  if (!s.tariff?.isSet) tips.push({ type: 'warning', title: 'Tarifingizni kiriting', text: "Bazaviy narx va 1 km narxini kiriting. Shunda har bir yetkazish uchun daromadingiz avtomatik hisoblanadi." });
  if (s.waitingOrders > 0) tips.push({ type: 'success', title: `${s.waitingOrders} ta buyurtma kuryer kutmoqda`, text: "Onlayn bo'ling, eng yaqin kuryerga avtomatik biriktiriladi." });
  if (s.peakHours?.[0]) tips.push({ type: 'idea', title: `Eng faol vaqt: ${s.peakHours[0].label}`, text: `So'nggi 30 kunda shu oraliqda ${s.peakHours[0].orders} ta buyurtma tushgan. Shu paytda onlayn bo'ling.` });
  if (s.hotZones?.[0]) tips.push({ type: 'idea', title: `${s.hotZones[0].name} atrofida turing`, text: `So'nggi 14 kunda bu do'kondan ${s.hotZones[0].orders} ta buyurtma chiqqan.` });
  if (s.acceptRate != null && s.acceptRate < 80) tips.push({ type: 'warning', title: "Rad etishlar ko'p", text: `Qabul qilish ulushi ${s.acceptRate}%. Kamroq rad etsangiz, sizga buyurtmalar tez-tez biriktiriladi.` });
  if (!tips.length) tips.push({ type: 'idea', title: "Onlayn bo'ling", text: "Kuryer onlayn va joylashuvi yangi bo'lsa, yangi buyurtmalar avtomatik biriktiriladi." });
  return tips.slice(0, 5);
}

function cargoFallback(s) {
  const tips = [];
  const money2 = (n) => Number(n).toLocaleString('ru-RU').replace(/,/g, ' ');
  if (!s.tariff?.isSet) tips.push({ type: 'warning', title: 'Tarifingizni kiriting', text: "Bazaviy narx va 1 km narxini kiriting. Mijozlar yo'nalish bo'yicha taxminiy narxni oldindan ko'radi." });
  if (s.counts?.new > 0) tips.push({ type: 'success', title: `${s.counts.new} ta yangi so'rov`, text: "Tez javob bering. Birinchi javob bergan tashuvchini mijozlar ko'proq tanlaydi." });
  const r = s.topRoutes?.find((x) => x.orders > 0) || s.topRoutes?.[0];
  if (r) {
    const cmp = r.yourPrice && r.marketPrice ? (r.yourPrice > r.marketPrice ? `Sizning narxingiz (${money2(r.yourPrice)} so'm) bozordan (${money2(r.marketPrice)} so'm) yuqori.` : `Narxingiz bozor darajasida yoki arzonroq (${money2(r.yourPrice)} so'm).`) : '';
    tips.push({ type: 'idea', title: `${r.from} → ${r.to}`, text: `${r.orders > 0 ? `So'nggi 60 kunda ${r.orders} ta buyurtma.` : "Xizmat viloyatlaringiz orasidagi yo'nalish."} ${cmp}`.trim() });
  }
  if (s.acceptRate != null && s.acceptRate < 70) tips.push({ type: 'warning', title: "Qabul qilish ulushi past", text: `So'rovlarning ${s.acceptRate}% qabul qilingan. Rad etishdan oldin narxni kelishib ko'ring.` });
  if (!tips.length) tips.push({ type: 'idea', title: "Profilni to'ldiring", text: "Mashina turi, sig'imi va xizmat viloyatlarini aniq kiriting. Mijozlar mos tashuvchini tezroq topadi." });
  return tips.slice(0, 5);
}

/** Sotuvchi analitikasi bo'yicha qisqa AI xulosa: { summary, highlights:[{type:'good'|'warn'|'idea', text}] } */
export async function sellerAiSummary({ shop, analytics: a }) {
  const fallback = sellerSummaryFallback(a);
  if (!aiEnabled()) return fallback;
  const system = `Sen kichik do'kon egasiga savdo hisobotini tushuntiradigan tahlilchisan. Analitika asosida qisqa xulosa yoz: nima yaxshi, nima xavotirli, nima qilish kerak. Raqamlarni so'mda va foizda keltir, ma'lumotda yo'q narsani o'ylab topma. FAQAT JSON obyekt qaytar: {"summary": "2–3 gap, o'zbek tilida (lotin)", "highlights": [{"type": "good" | "warn" | "idea", "text": "1 gap"}]}. highlights 3–4 ta bo'lsin.`;
  const compact = {
    stats: a.stats, week: a.week, prev: a.prev, thisMonth: a.thisMonth, prevMonth: a.prevMonth, status: a.status,
    topSold: a.topSold, peakHour: a.peakHour, bestWeekday: a.bestWeekday, unsoldCount: a.unsold?.length ?? 0,
    productCount: shop.product_count, hasLocation: shop.lat != null, last7Days: (a.byDay || []).slice(-7),
  };
  const raw = await ask({ system, user: `Do'kon: ${shop.name}\nAnalitika (JSON): ${JSON.stringify(compact)}`, maxTokens: 1200, json: true });
  try {
    const m = raw.match(/\{[\s\S]*\}/);
    const j = JSON.parse(m ? m[0] : raw);
    if (!j.summary) return fallback;
    const highlights = (Array.isArray(j.highlights) ? j.highlights : [])
      .filter((h) => h && h.text)
      .map((h) => ({ type: ['good', 'warn', 'idea'].includes(h.type) ? h.type : 'idea', text: String(h.text) }))
      .slice(0, 4);
    return { summary: String(j.summary), highlights };
  } catch {
    return fallback;
  }
}

function sellerSummaryFallback(a) {
  const s = a.stats || {};
  const w = a.week?.n ?? 0, p = a.prev?.n ?? 0;
  const trend = p > 0 ? Math.round(((w - p) / p) * 100) : null;
  const summary = !s.totalOrders
    ? "Hozircha buyurtmalar yo'q. Mahsulotlarni to'ldirib, do'kon havolasini ulashsangiz, birinchi sotuvlar tezroq keladi."
    : `Jami ${s.totalOrders} ta buyurtma, daromad ${money(s.revenue || 0)} so'm. Oxirgi 7 kunda ${w} ta buyurtma${trend != null ? `, oldingi haftaga nisbatan ${trend >= 0 ? '+' : ''}${trend}%` : ''}.`;
  const highlights = [];
  if (a.topSold?.[0]) highlights.push({ type: 'good', text: `Eng ko'p sotilgan: ${a.topSold[0].name}, ${a.topSold[0].qty} dona.` });
  if (s.views > 0) highlights.push({ type: 'idea', text: `Konversiya ${s.conversion}%: ${s.views} ta ko'rishdan ${s.totalOrders} ta buyurtma.` });
  if (a.unsold?.length) highlights.push({ type: 'warn', text: `${a.unsold.length} ta mahsulot hali sotilmagan, narx yoki rasmni yangilab ko'ring.` });
  return { summary, highlights };
}

/**
 * Foydalanuvchi qiziqishlari: Reels'da uzoq ko'rgan, layk bosgan, ko'rgan, sotib olgan mahsulotlari, qidiruvlari,
 * chatdagi savollari va obunalari asosida. Natija: { categories:[slug], keywords:[string], summary, source }
 */
export async function userInterests({ signals }) {
  const fallback = { ...interestsFallback(signals), source: 'rules' };
  const total = Object.values(signals).reduce((n, v) => n + (Array.isArray(v) ? v.length : 0), 0);
  if (!aiEnabled() || total < 3) return fallback;
  const system = `Sen onlayn bozor foydalanuvchisining qiziqishlarini aniqlaydigan tahlilchisan. Harakatlar: reels (uzoq ko'rgan mahsulotlar, ms — ko'rish vaqti), likes, views, orders, searches, chats, follows. Kategoriyalarni FAQAT shu ro'yxatdan tanla: ${CATEGORY_SLUGS.join(', ')}. Ma'lumotda yo'q qiziqishni o'ylab topma. FAQAT JSON obyekt qaytar: {"categories": ["slug"] (muhimlik tartibida, 1–5 ta), "keywords": ["mahsulot turi yoki brend, kichik harfda"] (3–8 ta), "summary": "1 gap, o'zbek tilida (lotin)"}.`;
  const raw = await ask({ system, user: `Harakatlar (JSON): ${JSON.stringify(signals)}`, maxTokens: 800, json: true });
  try {
    const m = raw.match(/\{[\s\S]*\}/);
    const j = JSON.parse(m ? m[0] : raw);
    const categories = (Array.isArray(j.categories) ? j.categories : []).map(String).filter((c) => CATEGORY_SLUGS.includes(c)).slice(0, 5);
    const keywords = [...new Set((Array.isArray(j.keywords) ? j.keywords : []).map((k) => String(k).toLowerCase().trim()).filter((k) => k.length >= 2 && k.length <= 30))].slice(0, 8);
    if (!categories.length && !keywords.length) return fallback;
    return { categories, keywords, summary: j.summary ? String(j.summary) : fallback.summary, source: 'ai' };
  } catch {
    return fallback;
  }
}

function interestsFallback(sig) {
  const weight = {};
  const add = (cat, n) => { if (cat) weight[cat] = (weight[cat] || 0) + n; };
  (sig.orders || []).forEach((x) => add(x.category, 4));
  (sig.likes || []).forEach((x) => add(x.category, 3));
  (sig.reels || []).forEach((x) => add(x.category, x.ms >= 3000 ? 2 : 0.5));
  (sig.views || []).forEach((x) => add(x.category, 1));
  const categories = Object.entries(weight).sort((a, b) => b[1] - a[1]).slice(0, 4).map(([k]) => k);
  const words = {};
  const count = (text, n) => String(text || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((t) => t.length >= 3).forEach((t) => { words[t] = (words[t] || 0) + n; });
  [...(sig.orders || []), ...(sig.likes || []), ...(sig.reels || []).filter((x) => x.ms >= 3000)].forEach((x) => count(x.name, 1));
  (sig.searches || []).forEach((q) => count(q, 2));
  const keywords = Object.entries(words).sort((a, b) => b[1] - a[1]).slice(0, 6).map(([k]) => k);
  return { categories, keywords, summary: keywords.length ? `Ko'proq qiziqadi: ${keywords.slice(0, 3).join(', ')}` : null };
}
