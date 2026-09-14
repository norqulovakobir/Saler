import Anthropic from '@anthropic-ai/sdk';
import { log } from './util.js';

const MODEL = process.env.AI_MODEL || 'claude-opus-5';
export const aiEnabled = () => Boolean(process.env.ANTHROPIC_API_KEY);
const client = aiEnabled() ? new Anthropic() : null;

const NO_AI = "AI yordamchi hozircha o'chirilgan (server ANTHROPIC_API_KEY sozlanmagan). Do'konlar va mahsulotlarni katalogdan qidiring.";

function textOf(msg) {
  return msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('').trim();
}

async function ask({ system, history = [], user, effort = 'low', maxTokens = 2000 }) {
  if (!client) return NO_AI;
  const messages = [...history.filter((m) => m.text).map((m) => ({ role: m.role === 'assistant' ? 'assistant' : 'user', content: m.text })), { role: 'user', content: user }];
  // Ketma-ket bir xil rollar API tomonidan birlashtiriladi; birinchisi user bo'lishi shart
  while (messages.length && messages[0].role !== 'user') messages.shift();
  try {
    const res = await client.messages.create({
      model: MODEL,
      max_tokens: maxTokens,
      system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
      output_config: { effort },
      messages,
    });
    if (res.stop_reason === 'refusal') return "Bu so'rovga javob bera olmayman.";
    return textOf(res) || '...';
  } catch (e) {
    log('AI xato', e?.status, e?.message);
    if (e instanceof Anthropic.AuthenticationError) return "AI kaliti noto'g'ri (ANTHROPIC_API_KEY).";
    if (e instanceof Anthropic.RateLimitError) return 'AI hozir band, birozdan keyin urinib ko\'ring.';
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
  const system = `Sen Saler AI — O'zbekistondagi mahalliy do'konlar bozorining xarid yordamchisisan. Foydalanuvchi bilan o'zbek tilida (lotin), qisqa va aniq gaplash. Faqat quyidagi katalogdagi do'kon va mahsulotlarni tavsiya qil, o'ylab topma. Narxlarni so'mda yoz. Foydalanuvchi joylashuvi ma'lum bo'lsa yaqinroq do'konlarni afzal ko'r. Mos mahsulot topilmasa, buni ochiq ayt va nima qidirish mumkinligini taklif qil.

KATALOG:
${catalog || "(hozircha do'konlar yo'q)"}`;
  const user = userLoc ? `${message}\n\n(Foydalanuvchi joylashuvi: ${userLoc.lat}, ${userLoc.lon})` : message;
  return ask({ system, history, user });
}

/** Do'kon sotuvchisi nomidan chat (AI sotuvchi) */
export async function shopChatReply({ message, history, shop, products }) {
  const ps = products.map((p) => `- [${p.id}] ${p.name} — ${money(p.price)} so'm${p.description ? `. ${p.description.slice(0, 200)}` : ''}`).join('\n');
  const system = `Sen "${shop.name}" do'konining onlayn sotuvchisisan${shop.sellerName ? `, isming ${shop.sellerName}` : ''}. O'zbek tilida (lotin), do'stona va qisqa javob ber. Faqat shu do'kon mahsulotlari haqida gapir, narxlarni aniq ayt, mavjud bo'lmagan narsani va'da qilma. Xaridor buyurtma bermoqchi bo'lsa, ilovadagi "Buyurtma berish" tugmasini bosishni ayt. Do'kon telefoni: ${shop.phone || 'ko\'rsatilmagan'}.${shop.description ? ` Do'kon haqida: ${shop.description}` : ''}

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
  if (!client) return fallback;
  const system = `Sen kichik do'konlar uchun savdo maslahatchisisan. Berilgan statistikaga qarab 3–5 ta aniq, amaliy maslahat ber. FAQAT JSON massiv qaytar, boshqa matn yozma. Har bir element: {"type": "idea" | "warning" | "success", "title": "qisqa sarlavha", "text": "1–2 gap, o'zbek tilida (lotin)"}.`;
  const user = `Do'kon: ${shop.name}\nStatistika (JSON): ${JSON.stringify(stats)}`;
  const raw = await ask({ system, user, maxTokens: 1500 });
  try {
    const m = raw.match(/\[[\s\S]*\]/);
    const arr = JSON.parse(m ? m[0] : raw);
    const tips = arr.filter((t) => t && t.title && t.text).map((t) => ({ type: ['idea', 'warning', 'success'].includes(t.type) ? t.type : 'idea', title: String(t.title), text: String(t.text) }));
    return tips.length ? tips.slice(0, 6) : fallback;
  } catch {
    return fallback;
  }
}
