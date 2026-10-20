// 「提醒哄睡 + 辅助哄睡」给家长看的文案（#38）
//
// 状态：育儿指南已审（2026-10-20），按意见修改后可进开发。
// 原稿：/workspace/honghong-sleep-copy-draft.md，以及 #38 评论 6286515825（修订后的全文）。
// **这里的每一句都要和审定稿逐字一致**，改文案先找育儿指南审，再同步改这里和 test/soothe_copy_test.dart。
//
// 写法：`**…**` 表示加粗（和审定稿里的加粗一致），显示时去掉星号。纯文本用 [plainCopy]。
// 硬规则（有单元测试把关）：
// - 只说"可能"，给范围不给精确时间，带"每个宝宝不一样"；
// - 播放页固定提示：音量开小、至少 2 米、不放进小床或床栏、定时关闭、不能代替大人看护；不写分贝数；
// - 「绝不能摇晃宝宝」、撑不住时先仰卧放进安全的小床；
// - 安全睡眠（仰卧、平整不倾斜、不放杂物）、可能生病时不要用哄睡处理、急症提示直接复用 #30 的 [stageEmergencyLine]；
// - 不写药物建议、不做诊断。
//
// 纯 Dart（不依赖 Flutter）。

import '../../domain/soothe/wake_window.dart';
import '../stage/stage_copy.dart' show stageEmergencyLine;

export '../stage/stage_copy.dart' show stageEmergencyLine;

/// 去掉加粗标记
String plainCopy(String s) => s.replaceAll('**', '');

// ───────── A. 清醒时长提醒（首页提醒卡） ─────────

/// A1 标题。{X} = [formatAwakeApprox]
String reminderTitle(Duration awake) => '宝宝醒了约 ${formatAwakeApprox(awake)}，可能快困了';

/// A1 正文（困倦信号放最前面）
const reminderBody =
    '留意困倦信号：打哈欠、眼神发直、揉眼睛、扭开脸、皱眉、握拳、手脚乱动、身体往后打挺。看到了就可以开始哄睡，不用等到哭。'
    '如果距离上次喂奶超过 2 小时左右，可能是饿了，拿不准就先喂一喂。每个宝宝不一样，以宝宝的信号为准。';

const reminderStart = '开始哄睡';

/// 本次醒着期间不再提醒
const reminderNotSleepy = '还不困';

/// 大字体下折叠正文（设计终稿 final-08）
const reminderExpand = '展开看困倦信号';
const reminderCollapse = '收起';
const reminderCollapseSemantics = '收起困倦信号';

/// A2：按月龄的清醒时长（只放在哄睡页，Liam 2026-10-20 确认；提醒卡上不放）
const Map<WakeBand, String> wakeRangeCopy = {
  WakeBand.months0to3: '这么大的宝宝，可能醒 1–1.5 小时就困了，有的宝宝能醒 2 小时左右',
  WakeBand.months3to6: '可能醒 1.5–3 小时会困',
  WakeBand.months6to12: '可能醒 2–3 小时会困',
};

/// A3：一天总睡眠参考（只作参考，不给作息表）。v1 界面没有放这一句（终稿没有画），文案先留着。
const totalSleepNote = '0–3 个月每天大约睡 13–18 小时，4–11 个月大约 12–16 小时。每个宝宝不一样，只要精神、吃奶、长体重都好，一般不用太担心。';

// ───────── B. 辅助哄睡 ─────────

/// B1：播放页顶部固定提示（每次打开都显示，不能关闭）
const playerFixedNotes = ['音量开小，大概跟洗澡水声差不多或更小，不要开到最大。手机离宝宝至少 2 米，**不要放进小床里，也不要放在床栏上**。', '到时间会自动关掉（默认 30 分钟），不要整晚一直开着。', '哄睡声音只是辅助，**不能代替大人看护**。宝宝睡着后请照常照看。'];

class SootheStep {
  const SootheStep({required this.title, required this.body});
  final String title;
  final String body;
}

/// B2：哄睡步骤（6 张卡）。第 6 步"放回小床"的正文用 C1 的两句（审定稿写的是"见 C1"）。
final sootheSteps = [
  const SootheStep(title: '调暗灯光、安静下来', body: '拉上窗帘，关掉大灯，说话小声一点。'),
  const SootheStep(
    title: '包裹（可选）',
    body:
        '用薄包巾包住身体，**腿和髋部要能自由弯曲、向两边张开**。宝宝**开始想翻身就停止包裹**。包着的宝宝只能仰卧放下。不要用加重的包巾。'
        '留意别热着，出汗、头发潮、呼吸快就是太热了。',
  ),
  const SootheStep(title: '轻轻摇、轻拍', body: '抱在怀里，扶好头颈，慢慢走动或小幅度、有节奏地轻摇、轻拍。'),
  const SootheStep(title: '嘘声 / 白噪音', body: '在耳边轻轻发出"嘘——"，或打开哄哄的嘘声、白噪音（音量开小，手机离远）。'),
  const SootheStep(title: '吸吮', body: '可以给安抚奶嘴，或让宝宝吸吮。母乳喂养的宝宝，等喂奶顺利了再给安抚奶嘴；宝宝不要就别硬塞。'),
  SootheStep(title: '放回小床', body: safeSleepLines.join('\n')),
];

/// 第 3 步（轻摇）的下标；红字紧跟在这一步下面
const shakeStepIndex = 2;

/// 第 3 步后面紧跟的红字；哭闹高峰期时在步骤页置顶（#30 的 cryingPeak）
const neverShakeLine = '**绝不能摇晃宝宝**。轻摇是指动作很小、很慢的晃动，不是甩动或摇晃。';

/// 撑不住时（每张步骤卡下面都有）
const overwhelmedLine =
    '哄了很久还在哭、你快撑不住了：先把宝宝**仰卧放进安全的小床**，离开几分钟缓一缓，或者请家人接手。'
    '等自己平静下来，大约 10–15 分钟后再回去看看宝宝。';

// ───────── C. 必带的安全内容（结果页入口、哄睡页、步骤页、安全须知） ─────────

/// C1：安全睡眠
const safeSleepLines = ['宝宝睡着后，**仰卧**放回**平整、不倾斜**的小床或婴儿床。床上**不放枕头、被子、毛绒玩具**。', '**不要让宝宝在倾斜的摇椅、安抚椅、秋千、汽车座椅里长时间睡**。在里面睡着了，就尽快抱到平整的小床上。'];

/// C2：可能生病时不要用哄睡处理（结果页建议卡、哄睡页、步骤页、安全须知都要带；提醒卡不放，Liam 2026-10-20 确认）
const sickNoSootheLine = '宝宝如果可能生病了（比如发烧、精神差、拒奶），**不要用哄睡的办法处理哭闹**，请先看医生。';

/// C2 补充（放在急症提示后面）
const unusualCryLine = '哭声和平时明显不一样，或者怎么哄都哄不好、持续很久，也请及时就医。';

/// C3
const disclaimerLine = '以上只是参考，不能替代医生判断，也不能代替大人看护。';

/// 急症提示：和 #30 完全相同（[stageEmergencyLine]），这里只是起个别名，方便测试检查"每个面板都有"。
const sootheEmergencyLine = stageEmergencyLine;

// ───────── 小标题和设计补充的文字（设计终稿里标「建议文案」，不含医学内容） ─────────

const safetyHeading = '安全须知';
const safetySheetTitle = '哄睡安全须知';

/// 第一次自动弹出安全须知时标题下面的一行（育儿指南 2026-10-20 审过：可以用）
const safetyFirstTimeLine = '第一次使用哄睡，先花半分钟看看';
const safetySleepHeading = '安全睡眠';
const safetySwaddleHeading = '包裹';
const safetySoundHeading = '哄睡声音';
const safetySickHeading = '可能生病时';
const safetyGotIt = '知道了';

const sootheTitle = '哄睡';
const stepsTitle = '哄睡步骤';
const stepsEntry = '跟着哄睡步骤做';
const asleepStartLog = '睡着了 · 开始记录睡觉';
const asleepAlreadyLogging = '睡觉已在计时';
const prevStep = '上一步';
const nextStepPrefix = '下一步：';
const stepsDone = '完成';

// ───────── 哄睡声音（S-3，界面文字，不含医学内容） ─────────

const playerSoundHeading = '声音';
const playerDefaultTag = '默认';
String playerVolumeLabel(double v) => '音量 ${(v * 100).round()}%';
const playerVolumeMax = '最高 70%';
const playerTimerHeading = '定时关闭';
String playerTimerOption(int minutes) => '$minutes 分钟';
const playerPlay = '开始播放';
const playerStop = '停止';
const playerResume = '继续';
const playerExtra = '再播 15 分钟';
const playerRetry = '再试一次';

/// 「粉噪音播放中 · 28:41 后自动关闭」（终稿 03）
String playerPlayingStatus(String sound, String left) => '**$sound播放中** · $left 后自动关闭';

/// 步骤页底部迷你条「粉噪音播放中 · 26:10 后关闭」（终稿 04）
String playerMiniStatus(String sound, String left) => '**$sound播放中** · $left 后关闭';

/// 被来电等打断，或在锁屏上按了暂停（定稿边界规则 1）
const playerPausedStatus = '**已暂停** · 点继续';

/// 定时结束（终稿 11）「已自动关闭 · 粉噪音播放了 30 分钟」
String playerEndedStatus(String sound, int minutes) => '**已自动关闭** · $sound播放了 $minutes 分钟';

/// 声音没能播放：退回到 B2 第 4 步里自己发"嘘——"的办法（审定文案原句的前半段）
const playerErrorLine = '声音没能播放。可以在耳边轻轻发出"嘘——"。';
