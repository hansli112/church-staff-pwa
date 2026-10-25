// The languages the backend writes in, and everything it writes in each:
// pushes, the church page before the app starts, a new church's services.
// Matches AppLanguage in app/lib/core/languages.dart; terms per
// docs/i18n-glossary.md.

/** An AppLanguage tag, as users/{uid}.appLocale holds it. */
export type Language = 'zh-Hant' | 'zh-Hans' | 'en' | 'ja' | 'ko';

export const LANGUAGES: readonly Language[] = ['zh-Hant', 'zh-Hans', 'en', 'ja', 'ko'];

/**
 * The language for a BCP 47 tag the app speaks, as AppLanguage.of: Chinese
 * is Simplified when it says so, or comes from where Simplified is written
 * (China, Singapore, Malaysia) without saying Traditional; else Traditional.
 */
const speaks = (tag: string): Language | null => {
  const [primary, ...rest] = tag.toLowerCase().split(/[-_]/);
  if (primary === 'en' || primary === 'ja' || primary === 'ko') return primary;
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
const JA_WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];
const KO_WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];
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
  /** A `YYYY-MM-DD` day as pushes say it: 10/18, Oct 18, 10月18日. */
  shortDate(dateKey: string): string;
  /** The day with its weekday: 10/18（週日）, Oct 18 (Sun), 10月18日(日). */
  dateWithWeekday(dateKey: string): string;

  /**
   * Evening reminders' titles (notifications.ts): a greeting by [name]
   * (null when the member has none), then what follows. The days are in
   * the body, one a line, so the title gives no dates.
   */
  weekReminder(name: string | null): string;
  tomorrowReminder(name: string | null): string;
  /** Someone's duties on one day; [name] is the service's or event's. */
  dutyLine(name: string, duties: string[]): string;
  /** [day] is dateWithWeekday's. */
  datedDutyLine(day: string, line: string): string;
  /** Between the days of a reminder: one a line, as the self-hosted reminders had them. */
  lineSeparator: string;

  /** Roster changes (rosterChange.ts). [day] is the short date and the service's name; put on and taken off read alike. */
  eventMoved(title: string, day: string): string;
  putOn(day: string, duties: string[]): string;
  takenOff(day: string, duties: string[]): string;

  /** A member left (triggers.ts); [name] is theirs, null when they had none. */
  memberLeft(name: string | null): string;

  /** 申請加入 (joinRequests.ts): to admins, [name] asked to join (null when they have none), with what they wrote, if anything; to them, they were let in. */
  joinRequested(name: string | null, note: string): string;
  joinAllowed: string;

  /** 回報人數 (attendance.ts): the title, and the body for [group]'s meeting on [day] (dateWithWeekday's). */
  attendanceTitle: string;
  attendanceBody(group: string, day: string): string;

  /** The church page before the app starts (churchPage.ts). */
  appName: string;
  description: string;
  loading: string;
  inviteInvalid: string;
  inviteExpired: string;

  /** 線上支持 on ECPay's page and in its back office (ItemName, TradeDesc): plain words, at most 200 characters (fundingEcpay.ts). */
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
  weekReminder: (name) => `平安${name ? ` ${name}` : ''}，這週的服事`,
  tomorrowReminder: (name) => `平安${name ? ` ${name}` : ''}，明天的服事`,
  dutyLine: (name, duties) => `${name} ${duties.join('、')}`,
  datedDutyLine: (day, line) => `${day}${line}`,
  lineSeparator: '\n',
  // A name the church typed sits in 「」: no space to judge between it and Chinese.
  eventMoved: (title, day) => `「${title}」改到 ${day}`,
  putOn: (day, duties) => `你被排進 ${day}：${duties.join('、')}`,
  takenOff: (day, duties) => `你被移出 ${day}：${duties.join('、')}`,
  memberLeft: (name) => (name ? `「${name}」退出了教會` : '有人退出了教會'),
  joinRequested: (name, note) => `${name ? `「${name}」申請加入教會` : '有人申請加入教會'}${note ? `：${note}` : ''}`,
  joinAllowed: '管理員允許你加入了，歡迎！',
  attendanceTitle: '填寫人數',
  attendanceBody: (group, day) => `「${group}」${day}的聚會有幾個人？`,
  appName: '馬大別忙',
  supportItem: '支持馬大別忙的雲端費用',
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
  weekReminder: (name) => `平安${name ? ` ${name}` : ''}，这周的事奉`,
  tomorrowReminder: (name) => `平安${name ? ` ${name}` : ''}，明天的事奉`,
  dutyLine: zhHant.dutyLine,
  datedDutyLine: zhHant.datedDutyLine,
  lineSeparator: '\n',
  eventMoved: (title, day) => `“${title}”改到 ${day}`,
  putOn: (day, duties) => `你被排入 ${day}：${duties.join('、')}`,
  takenOff: (day, duties) => `你被移出 ${day}：${duties.join('、')}`,
  memberLeft: (name) => (name ? `“${name}”退出了教会` : '有人退出了教会'),
  joinRequested: (name, note) => `${name ? `“${name}”申请加入教会` : '有人申请加入教会'}${note ? `：${note}` : ''}`,
  joinAllowed: '管理员允许你加入了，欢迎！',
  attendanceTitle: '填写人数',
  attendanceBody: (group, day) => `“${group}”${day}的聚会有几个人？`,
  appName: '马大别忙',
  supportItem: '支持马大别忙的云端费用',
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
  weekReminder: (name) => (name ? `Hi ${name}, your serving this week` : 'Your serving this week'),
  tomorrowReminder: (name) => (name ? `Hi ${name}, your serving tomorrow` : 'Your serving tomorrow'),
  dutyLine: (name, duties) => `${name}: ${duties.join(', ')}`,
  datedDutyLine: (day, line) => `${day} ${line}`,
  lineSeparator: '\n',
  eventMoved: (title, day) => `${title} moved to ${day}`,
  putOn: (day, duties) => `You’re on ${day}: ${duties.join(', ')}`,
  takenOff: (day, duties) => `You’re no longer on ${day}: ${duties.join(', ')}`,
  memberLeft: (name) => `${name ?? 'Someone'} left the church`,
  joinRequested: (name, note) => `${name ?? 'Someone'} asked to join the church${note ? `: ${note}` : ''}`,
  joinAllowed: 'An admin let you in. Welcome!',
  attendanceTitle: 'Attendance',
  attendanceBody: (group, day) => `How many came to ${group} on ${day}?`,
  appName: 'Martha, sit',
  supportItem: 'Support for the server costs of Martha, sit',
  description:
    '“Martha, Martha,” the Lord answered, “you are worried and upset about many things, but few things are needed—or indeed only one. Mary has chosen what is better, and it will not be taken away from her.” (Luke 10:41–42)',
  loading: 'Loading…',
  // app/lib/l10n/app_en.arb's.
  inviteInvalid: 'Couldn’t find this invite. Check the code, or ask an admin for a new invite.',
  inviteExpired: 'This invite has expired. Ask an admin for a new one.',
  placeholder: 'TBD',
  newChurchServices: [sunday('Sunday Service', ['Host', 'Worship Leader', 'Piano', 'Sound', 'Slides', 'Usher'], ['Communion', 'Baptism'])],
};

// CLDR's MMMd and MMMEd, as the app shows them.
const ja: Words = {
  shortDate: (k) => `${ymd(k)[1]}月${ymd(k)[2]}日`,
  dateWithWeekday: (k) => `${ja.shortDate(k)}(${JA_WEEKDAYS[weekday(k)]})`,
  weekReminder: (name) => (name ? `${name}さん、今週の奉仕` : '今週の奉仕'),
  tomorrowReminder: (name) => (name ? `${name}さん、明日の奉仕` : '明日の奉仕'),
  dutyLine: zhHant.dutyLine,
  datedDutyLine: (day, line) => `${day} ${line}`,
  lineSeparator: '\n',
  eventMoved: (title, day) => `${title}の日程が${day}に変更されました`,
  putOn: (day, duties) => `${day}の担当になりました：${duties.join('、')}`,
  takenOff: (day, duties) => `${day}の担当から外れました：${duties.join('、')}`,
  memberLeft: (name) => `${name ?? 'メンバー'}が教会を退出しました`,
  joinRequested: (name, note) => `${name ?? 'どなたか'}が教会への参加を申請しました${note ? `：${note}` : ''}`,
  joinAllowed: '管理者が参加を承認しました。ようこそ！',
  attendanceTitle: '人数の記録',
  attendanceBody: (group, day) => `${day}の「${group}」には何人集まりましたか？`,
  appName: 'マルタ、ひと休み',
  supportItem: 'Martha, sit サーバー費用の応援',
  description: '「マルタ、マルタ、あなたは多くのことに思い悩み、心を乱している。しかし、必要なことはただ一つだけである。マリアは良い方を選んだ。それを取り上げてはならない。」（ルカによる福音書 10:41–42）',
  loading: '読み込み中…',
  // app/lib/l10n/app_ja.arb's.
  inviteInvalid: 'この招待が見つかりません。招待コードを確認するか、管理者に新しい招待をもらってください。',
  inviteExpired: 'この招待は期限切れです。管理者に新しい招待をもらってください。',
  placeholder: '未定',
  newChurchServices: [sunday('主日礼拝', ['司会', '賛美リード', '奏楽', '音響', 'スライド', '受付'], ['聖餐式', '洗礼式'])],
};

const ko: Words = {
  shortDate: (k) => `${ymd(k)[1]}월 ${ymd(k)[2]}일`,
  dateWithWeekday: (k) => `${ko.shortDate(k)} (${KO_WEEKDAYS[weekday(k)]})`,
  weekReminder: (name) => (name ? `${name} 님, 이번 주 봉사` : '이번 주 봉사'),
  tomorrowReminder: (name) => (name ? `${name} 님, 내일 봉사` : '내일 봉사'),
  dutyLine: en.dutyLine,
  datedDutyLine: (day, line) => `${day} ${line}`,
  lineSeparator: '\n',
  eventMoved: (title, day) => `${title} 일정 변경: ${day}`,
  putOn: (day, duties) => `${day} 봉사에 배정됐어요: ${duties.join(', ')}`,
  takenOff: (day, duties) => `${day} 봉사에서 빠졌어요: ${duties.join(', ')}`,
  memberLeft: (name) => (name ? `${name} 님이 교회를 나갔어요` : '멤버 한 명이 교회를 나갔어요'),
  joinRequested: (name, note) =>
    `${name ? `${name} 님이 교회 가입을 신청했어요` : '누군가 교회 가입을 신청했어요'}${note ? `: ${note}` : ''}`,
  joinAllowed: '관리자가 가입을 승인했어요. 환영해요!',
  attendanceTitle: '인원 기록',
  attendanceBody: (group, day) => `${day} ${group}에 몇 명이 모였나요?`,
  appName: '마르다의 쉼표',
  supportItem: '마르다의 쉼표 서버 비용 후원',
  description: '마르다야 마르다야 네가 많은 일로 염려하고 근심하나 몇 가지만 하든지 혹은 한 가지만이라도 족하니라 마리아는 이 좋은 편을 택하였으니 빼앗기지 아니하리라 (누가복음 10:41–42)',
  loading: '불러오는 중…',
  // app/lib/l10n/app_ko.arb's.
  inviteInvalid: '초대를 찾을 수 없어요. 초대 코드를 확인하거나 관리자에게 새 초대를 요청해 주세요.',
  inviteExpired: '만료된 초대예요. 관리자에게 새 초대를 요청해 주세요.',
  placeholder: '미정',
  newChurchServices: [sunday('주일예배', ['사회', '찬양 인도', '반주', '음향', '자막', '안내'], ['성찬', '세례'])],
};

const WORDS: Record<Language, Words> = { 'zh-Hant': zhHant, 'zh-Hans': zhHans, en, ja, ko };

export const words = (language: Language): Words => WORDS[language];

/** A website page in [language]: Traditional Chinese at the root, the others under /en/ and so on (scripts/build-site.mjs). */
export const sitePath = (language: Language, path: string) => (language === 'zh-Hant' ? path : `/${language}${path}`);
