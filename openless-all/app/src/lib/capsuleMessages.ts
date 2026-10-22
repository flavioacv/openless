import type { TFunction } from 'i18next';
import type { CapsuleState } from './types';

const KNOWN_MESSAGE_KEYS: Record<string, string> = {
  // Completion / insertion states
  已输入: 'capsule.insertedDone',
  Inserted: 'capsule.insertedDone',
  '已发送粘贴，请确认': 'capsule.pasteSent',
  PasteSent: 'capsule.pasteSent',
  '已复制，请手动粘贴': 'capsule.copiedFallback',
  CopiedFallback: 'capsule.copiedFallback',
  处理完成: 'capsule.processedDone',
  NotRequested: 'capsule.processedDone',

  // Preparation / download
  '正在准备语音…': 'capsule.preparingVoice',
  '正在准备语音...': 'capsule.preparingVoice',
  '正在下载 CPU 模型，首次使用可能较慢…': 'capsule.downloadingModel',
  '正在下载 CPU 模型，首次使用可能较慢...': 'capsule.downloadingModel',

  // Selection polish notices
  '正在润色...': 'capsule.selectionPolish.polishing',
  '正在润色…': 'capsule.selectionPolish.polishing',
  已替换: 'capsule.selectionPolish.replaced',
  未选中内容: 'capsule.selectionPolish.noSelection',
  '润色失败，请重试': 'capsule.selectionPolish.failed',

  // Voice engine and pipeline errors
  请允许麦克风权限后重试: 'capsule.errors.permissionDenied',
  PermissionDenied: 'capsule.errors.permissionDenied',
  另一个语音任务正在进行: 'capsule.errors.busy',
  Busy: 'capsule.errors.busy',
  已取消: 'capsule.cancelled',
  Cancelled: 'capsule.cancelled',
  '识别或润色失败，请重试': 'capsule.errors.providerOrNetwork',
  Provider: 'capsule.errors.providerOrNetwork',
  Network: 'capsule.errors.providerOrNetwork',
  Timeout: 'capsule.errors.providerOrNetwork',
  '录音或输入失败，请重试': 'capsule.errors.platformError',
  Platform: 'capsule.errors.platformError',
  '输入或设置无效，请检查后重试': 'capsule.errors.invalidArgument',
  InvalidArgument: 'capsule.errors.invalidArgument',
  '当前状态无法完成此操作，请重试': 'capsule.errors.invalidState',
  InvalidState: 'capsule.errors.invalidState',
  当前配置或平台不支持此操作: 'capsule.errors.unsupported',
  Unsupported: 'capsule.errors.unsupported',
  '保存结果失败，请检查磁盘后重试': 'capsule.errors.persistenceError',
  Persistence: 'capsule.errors.persistenceError',
  '无法确认是否已输入，请检查目标应用': 'capsule.errors.outcomeUnknown',
  OutcomeUnknown: 'capsule.errors.outcomeUnknown',
  '处理遇到内部错误，请重试': 'capsule.errors.internalError',
  Internal: 'capsule.errors.internalError',
  '处理失败，请重试': 'capsule.errors.genericError',
  'QA 处理失败，请重试': 'capsule.errors.qaError',
};

const CHINESE_CHAR_REGEX = /[\u4e00-\u9fa5]/;

/**
 * Translates backend-generated capsule and voice notifications into the active UI language.
 *
 * If a message matches a known system string, status or error code, it returns the localized
 * translation via `t()`. If the user is in a non-Chinese locale and an unmapped Chinese string
 * arrives on an error state, a localized generic error is used to prevent untranslated text.
 */
export function translateCapsuleMessage(
  message: string | null | undefined,
  t: TFunction,
  state?: CapsuleState,
): string | undefined {
  if (!message || !message.trim()) {
    return state === 'error' ? t('capsule.error') : undefined;
  }

  const trimmed = message.trim();

  // 1. Check exact known map
  const mappedKey = KNOWN_MESSAGE_KEYS[trimmed];
  if (mappedKey) {
    const translated = t(mappedKey);
    if (translated && translated !== mappedKey) {
      return translated;
    }
  }

  // 2. Direct i18n key passed
  if (
    trimmed.startsWith('capsule.') ||
    trimmed.startsWith('common.') ||
    trimmed.startsWith('settings.')
  ) {
    const translated = t(trimmed);
    if (translated && translated !== trimmed) {
      return translated;
    }
  }

  // 3. Inserted count pattern (e.g. "已插入 42" or "Inserted 42")
  const countMatch = trimmed.match(/^(?:已插入|Inserted)\s+(\d+)/);
  if (countMatch) {
    return t('capsule.inserted', { count: Number(countMatch[1]) });
  }

  // 4. Handle remaining Chinese text when user selected a non-Chinese UI language
  //    (like Portuguese, English, Spanish, etc.)
  const currentLang = (t as unknown as { lng?: string })?.lng || '';
  const isNonChineseLocale = !currentLang.toLowerCase().startsWith('zh');

  if (isNonChineseLocale && CHINESE_CHAR_REGEX.test(trimmed)) {
    if (state === 'error') {
      return t('capsule.errors.genericError', { defaultValue: t('capsule.error') });
    }
    if (state === 'done') {
      return t('capsule.insertedDone', { defaultValue: trimmed });
    }
    if (state === 'cancelled') {
      return t('capsule.cancelled');
    }
  }

  return trimmed;
}
