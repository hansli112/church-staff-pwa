// The languages the backend writes in, and everything it writes in each:
// pushes, the church page before the app starts, a new church's services.
// Matches AppLanguage in app/lib/core/languages.dart; terms per
// docs/i18n-glossary.md.

/** An AppLanguage tag, as users/{uid}.appLocale holds it. */
export type Language = 'zh-Hant' | 'zh-Hans' | 'en';

export const LANGUAGES: readonly Language[] = ['zh-Hant', 'zh-Hans', 'en'];

/**
 * The language for a BCP 47 tag the app speaks, as AppLanguage.of: Chinese
 * is Simplified when it says so, or comes from where Simplified is written
 * (China, Singapore, Malaysia) without saying Traditional; else Traditional.
 */
const speaks = (tag: string): Language | null => {
  const [primary, ...rest] = tag.toLowerCase().split(/[-_]/);
  if (primary === 'en') return 'en';
  if (primary !== 'zh') return null;
  const script = rest.find((s) => s.length === 4);
  const region = rest.find((s) => s.length === 2);
  return script === 'hans' || (!script && ['cn', 'sg', 'my'].includes(region ?? '')) ? 'zh-Hans' : 'zh-Hant';
};

/**
 * The language to write to a person in, from the AppLanguage tag their
 * app says it shows (users/{uid}.appLocale, or sent with a call). No tag:
 * Traditional Chinese, the only language of apps from before there were
 * others. One these functions do not know yet (an app newer than them):
 * English, as the app falls back to.
 */
export function languageOf(tag: unknown): Language {
  if (typeof tag !== 'string' || !tag) return 'zh-Hant';
  return speaks(tag) ?? 'en';
}

/**
 * The language for a browser sending [acceptLanguage], as the app picks
 * one following the device (AppLanguage.resolve): the first on its list,
 * by weight, the app speaks, else English.
 */
export function browserLanguage(acceptLanguage: string | undefined): Language {
  const ranked = (acceptLanguage ?? '')
    .split(',')
    .map((part, i) => {
      const [tag, ...params] = part.trim().split(';');
      const weight = params.find((p) => /^\s*q=/i.test(p));
      // A weight that is not a number leaves the entry out.
      const q = weight === undefined ? 1 : Number(/^\s*q=([\d.]+)\s*$/i.exec(weight)?.[1] ?? NaN);
      return { tag: tag.trim(), q, i };
    })
    .filter((l) => l.tag && l.q > 0)
    .sort((a, b) => b.q - a.q || a.i - b.i);
  return ranked.map((l) => speaks(l.tag)).find((l) => l !== null) ?? 'en';
}

const ymd = (dateKey: string) => dateKey.split('-').map(Number);
const weekday = (dateKey: string) => {
  const [y, m, d] = ymd(dateKey);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
};

const ZH_WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];
const EN_WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const EN_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** A new church's services. Its name and duties are the church's own from then on. */
export interface NewService {
  id: string;
  name: string;
  weekday: number;
  enabled: boolean;
  duties: string[];
  events: { name: string; color: number }[];
}

/** Everything the backend writes in one language. */
export interface Words {
  /** A `YYYY-MM-DD` day as pushes say it: 10/18, Oct 18. */
  shortDate(dateKey: string): string;
  /** The day with its weekday: 10/18（週日）, Oct 18 (Sun). */
  dateWithWeekday(dateKey: string): string;

  /** Evening reminders (notifications.ts). */
  weekReminder(from: string, until: string): string;
  tomorrowReminder(day: string): string;
  /** Someone's duties on one day; [name] is the service's or event's. */
  dutyLine(name: string, duties: string[]): string;
  /** [day] is dateWithWeekday's. */
  datedDutyLine(day: string, line: string): string;
  lineSeparator: string;

  /** Roster changes (rosterChange.ts). [day] is the short date and the service's name. */
  eventMoved(title: string, day: string): string;
  putOn(day: string, duties: string[]): string;
  takenOff(day: string, duties: string[]): string;

  /** A member left (triggers.ts); [name] is theirs, or [someone] without one. */
  memberLeft(name: string): string;
  someone: string;

  /** The church page before the app starts (churchPage.ts). */
  appName: string;
  description: string;
  loading: string;
  inviteInvalid: string;
  inviteExpired: string;

  /** 線上支持 on NewebPay's page and in its back office: at most 50 bytes in UTF-8, in case NewebPay counts them (fundingNewebpay.ts). */
  supportItem: string;

  /** A new church's services (church.ts). */
  newChurchServices: NewService[];

  /** Written in a duty's people for "nobody yet", as the app shows it (nobodyYet). */
  placeholder: string;
}

const sunday = (name: string, duties: string[], events: string[]): NewService => ({
  id: 'sunday',
  name,
  weekday: 7,
  enabled: true,
  duties,
  events: [
    { name: events[0], color: 0 },
    { name: events[1], color: 4 },
  ],
});

const zhHant: Words = {
  shortDate: (k) => `${ymd(k)[1]}/${ymd(k)[2]}`,
  dateWithWeekday: (k) => `${zhHant.shortDate(k)}（週${ZH_WEEKDAYS[weekday(k)]}）`,
  weekReminder: (from, until) => `這週的服事（${from}–${until}）`,
  tomorrowReminder: (day) => `明天的服事（${day}）`,
  dutyLine: (name, duties) => `${name} ${duties.join('、')}`,
  datedDutyLine: (day, line) => `${day}${line}`,
  lineSeparator: '；',
  eventMoved: (title, day) => `${title}改到 ${day}`,
  putOn: (day, duties) => `你被排進 ${day}：${duties.join('、')}`,
  takenOff: (day, duties) => `${day} 的${duties.join('、')}已改由別人負責`,
  memberLeft: (name) => `${name} 退出了教會`,
  someone: '有人',
  appName: '馬大別忙',
  supportItem: '馬大別忙 雲端費用 線上支持',
  description:
    '馬大！馬大！你為許多的事思慮煩擾，但是不可少的只有一件；馬利亞已經選擇那上好的福分，是不能奪去的。（路加福音 10:41–42）',
  loading: '載入中…',
  // The app's errInviteInvalid and errInviteExpired (app/lib/l10n/app_zh.arb), word for word.
  inviteInvalid: '找不到這個邀請，請確認邀請碼，或向管理員要新的邀請',
  inviteExpired: '這個邀請過期了，請向管理員要新的邀請',
  placeholder: '待定',
  newChurchServices: [sunday('主日崇拜', ['司會', '敬拜', '司琴', '音控', '投影', '招待'], ['聖餐', '浸禮'])],
};

const zhHans: Words = {
  shortDate: zhHant.shortDate,
  dateWithWeekday: (k) => `${zhHans.shortDate(k)}（周${ZH_WEEKDAYS[weekday(k)]}）`,
  weekReminder: (from, until) => `这周的事奉（${from}–${until}）`,
  tomorrowReminder: (day) => `明天的事奉（${day}）`,
  dutyLine: zhHant.dutyLine,
  datedDutyLine: zhHant.datedDutyLine,
  lineSeparator: '；',
  eventMoved: (title, day) => `${title}改到 ${day}`,
  putOn: (day, duties) => `你被排进 ${day}：${duties.join('、')}`,
  takenOff: (day, duties) => `${day} 的${duties.join('、')}已改由别人负责`,
  memberLeft: (name) => `${name} 退出了教会`,
  someone: '有人',
  appName: '马大别忙',
  supportItem: '马大别忙 云端费用 线上支持',
  description:
    '马大！马大！你为许多的事思虑烦扰，但是不可少的只有一件；马利亚已经选择那上好的福分，是不能夺去的。（路加福音 10:41–42）',
  loading: '加载中…',
  // app/lib/l10n/app_zh_Hans.arb's.
  inviteInvalid: '找不到这个邀请，请确认邀请码，或向管理员要新的邀请',
  inviteExpired: '这个邀请已过期，请向管理员要新的邀请',
  placeholder: '待定',
  newChurchServices: [sunday('主日崇拜', ['领会', '敬拜主领', '司琴', '音控', '投影', '招待'], ['圣餐', '浸礼'])],
};

const en: Words = {
  shortDate: (k) => `${EN_MONTHS[ymd(k)[1] - 1]} ${ymd(k)[2]}`,
  dateWithWeekday: (k) => `${en.shortDate(k)} (${EN_WEEKDAYS[weekday(k)]})`,
  weekReminder: (from, until) => `Serving this week (${from}–${until})`,
  tomorrowReminder: (day) => `Serving tomorrow (${day})`,
  dutyLine: (name, duties) => `${name}: ${duties.join(', ')}`,
  datedDutyLine: (day, line) => `${day} ${line}`,
  lineSeparator: '; ',
  eventMoved: (title, day) => `${title} moved to ${day}`,
  putOn: (day, duties) => `You’re on ${day}: ${duties.join(', ')}`,
  takenOff: (day, duties) => `Someone else now has ${duties.join(', ')} for ${day}`,
  memberLeft: (name) => `${name} left the church`,
  someone: 'Someone',
  appName: 'Martha, sit',
  supportItem: 'Martha, sit server costs support',
  description:
    '“Martha, Martha,” the Lord answered, “you are worried and upset about many things, but few things are needed—or indeed only one. Mary has chosen what is better, and it will not be taken away from her.” (Luke 10:41–42)',
  loading: 'Loading…',
  // app/lib/l10n/app_en.arb's.
  inviteInvalid: 'Couldn’t find this invite. Check the code, or ask an admin for a new invite.',
  inviteExpired: 'This invite has expired. Ask an admin for a new one.',
  placeholder: 'TBD',
  newChurchServices: [sunday('Sunday Service', ['Host', 'Worship Leader', 'Piano', 'Sound', 'Slides', 'Usher'], ['Communion', 'Baptism'])],
};

const WORDS: Record<Language, Words> = { 'zh-Hant': zhHant, 'zh-Hans': zhHans, en };

export const words = (language: Language): Words => WORDS[language];

/** A website page in [language]: Traditional Chinese at the root, the others under /en/ and so on (scripts/build-site.mjs). */
export const sitePath = (language: Language, path: string) => (language === 'zh-Hant' ? path : `/${language}${path}`);
