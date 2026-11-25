import type { TFunction } from 'i18next';
import i18n from '../i18n';
import type { CapsuleState } from './types';

const KNOWN_MESSAGE_KEYS: Record<string, string> = {
  // Completion / insertion states
  已输入: 'capsule.insertedDone',
  Inserted: 'capsule.insertedDone',
  已完成: 'capsule.processedDone',
  '已发送粘贴，请确认': 'capsule.pasteSent',
  PasteSent: 'capsule.pasteSent',
  '已复制，请手动粘贴': 'capsule.copiedFallback',
  '已复制结果，请手动粘贴': 'capsule.copiedFallback',
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
  '正在润色选区...': 'capsule.selectionPolish.polishing',
  '正在润色选区…': 'capsule.selectionPolish.polishing',
  已替换: 'capsule.selectionPolish.replaced',
  未选中内容: 'capsule.selectionPolish.noSelection',
  '润色失败，请重试': 'capsule.selectionPolish.failed',
  已打开润色: 'capsule.selectionPolish.polishing',

  // Voice engine and pipeline errors
  请允许麦克风权限后重试: 'capsule.errors.permissionDenied',
  '需要麦克风权限，请在系统设置中允许 OpenLess 使用麦克风': 'capsule.errors.permissionDenied',
  PermissionDenied: 'capsule.errors.permissionDenied',
  另一个语音任务正在进行: 'capsule.errors.busy',
  '正在听写，请先结束录音': 'capsule.errors.busy',
  选区语音会话进行中: 'capsule.errors.busy',
  Busy: 'capsule.errors.busy',
  已取消: 'capsule.cancelled',
  Cancelled: 'capsule.cancelled',
  '识别或润色失败，请重试': 'capsule.errors.providerOrNetwork',
  '语音识别超时，请重试': 'capsule.errors.providerOrNetwork',
  '语音识别不可用，请重试': 'capsule.errors.providerOrNetwork',
  Provider: 'capsule.errors.providerOrNetwork',
  Network: 'capsule.errors.providerOrNetwork',
  Timeout: 'capsule.errors.providerOrNetwork',
  '录音或输入失败，请重试': 'capsule.errors.platformError',
  '未检测到麦克风，请连接麦克风后重试': 'capsule.errors.platformError',
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

const DIRECT_LOCALIZED_MESSAGES: Record<string, { pt: string; en: string }> = {
  '已打开预览，等待确认': {
    pt: 'Prévia aberta, aguardando confirmação',
    en: 'Preview opened, awaiting confirmation',
  },
  '选区超过 4000 字，未替换，以免删掉中间没有读到的原文': {
    pt: 'A seleção excede 4000 caracteres; não substituída para evitar perda de texto',
    en: 'Selection exceeds 4000 characters; not replaced to avoid truncating text',
  },
  '选区超过 4000 字，已停止，以免用截断结果覆盖并删掉中间原文': {
    pt: 'A seleção excede 4000 caracteres; interrompido para evitar perda de texto',
    en: 'Selection exceeds 4000 characters; stopped to avoid overwriting with truncated text',
  },
  '目标输入框不可用，请重新选择': {
    pt: 'O campo de destino está indisponível, selecione novamente',
    en: 'Target input field unavailable, please reselect',
  },
  '无法定位输入目标，请先点击文本框后再试': {
    pt: 'Não foi possível localizar o campo de destino; clique na caixa de texto e tente novamente',
    en: 'Cannot locate input target; click a text field and try again',
  },
  '选区已变化，未替换': {
    pt: 'A seleção mudou, texto não substituído',
    en: 'Selection changed, not replaced',
  },
  '请先选中文字，或将光标放在可输入的文本框中': {
    pt: 'Selecione um texto ou posicione o cursor em um campo editável primeiro',
    en: 'Select text or place the cursor in an editable text field first',
  },
  '编辑方案解析失败，请重试': {
    pt: 'Falha ao analisar o plano de edição, tente novamente',
    en: 'Failed to parse edit plan, please retry',
  },
  '未能生成有效编辑方案，请重试': {
    pt: 'Não foi possível gerar um plano de edição válido, tente novamente',
    en: 'Failed to generate a valid edit plan, please retry',
  },
  '编辑方案过于复杂，请缩短指令': {
    pt: 'O plano de edição é muito complexo, encurte a instrução',
    en: 'Edit plan is too complex, please shorten your instruction',
  },
  '编辑内容过长，请缩短选区或拆步操作': {
    pt: 'O conteúdo editado é muito longo, reduza a seleção ou divida em etapas',
    en: 'Edited content is too long, shorten the selection or split into steps',
  },
  '翻译结果与原文相同，请重试或调整指令': {
    pt: 'A tradução ficou idêntica ao original; tente novamente ou ajuste a instrução',
    en: 'Translation is identical to original; retry or adjust your instruction',
  },
  未识别到指令: {
    pt: 'Nenhuma instrução reconhecida',
    en: 'No instruction recognized',
  },
  请选择意图: {
    pt: 'Escolha como prosseguir',
    en: 'Please choose an action',
  },
  已提交问题: {
    pt: 'Pergunta enviada',
    en: 'Question submitted',
  },
  '未检测到麦克风，请连接麦克风后重试': {
    pt: 'Nenhum microfone detectado. Conecte um microfone e tente novamente',
    en: 'No microphone detected. Connect a microphone and try again',
  },
  '无法启动语音编辑，请确认已启用该功能并聚焦外部输入框': {
    pt: 'Não foi possível iniciar a edição por voz. Verifique se o recurso está ativado e se há um campo focado',
    en: 'Cannot start voice editing. Make sure the feature is enabled and an input field is focused',
  },
};

const BUILTIN_STYLE_NAME_KEYS: Record<string, string> = {
  原文: 'style.modes.raw.name',
  轻度润色: 'style.modes.light.name',
  清晰结构: 'style.modes.structured.name',
  正式表达: 'style.modes.formal.name',
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
  const currentLang = (
    (t as unknown as { lng?: string })?.lng ||
    i18n.resolvedLanguage ||
    i18n.language ||
    ''
  ).toLowerCase();
  const isNonChineseLocale = !currentLang.startsWith('zh');
  const isPt = currentLang.startsWith('pt');

  // 0. Check direct localized selection/voice messages first when non-Chinese
  if (isNonChineseLocale && DIRECT_LOCALIZED_MESSAGES[trimmed]) {
    return isPt ? DIRECT_LOCALIZED_MESSAGES[trimmed].pt : DIRECT_LOCALIZED_MESSAGES[trimmed].en;
  }

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

  // 3b. Style pack switch pattern (e.g. "已切换：轻度润色")
  const switchMatch = trimmed.match(/^已切换[：:]\s*(.+)$/);
  if (switchMatch && isNonChineseLocale) {
    const rawPackName = switchMatch[1].trim();
    const packKey = BUILTIN_STYLE_NAME_KEYS[rawPackName];
    const localizedPackName = packKey ? t(packKey, { defaultValue: rawPackName }) : rawPackName;
    return isPt ? `Estilo: ${localizedPackName}` : `Switched: ${localizedPackName}`;
  }

  // 3c. Recording start failure prefix (e.g. "录音启动失败: ...")
  if (trimmed.startsWith('录音启动失败') && isNonChineseLocale) {
    return t('capsule.errors.platformError', { defaultValue: t('capsule.error') });
  }

  // 4. Handle remaining Chinese text when user selected a non-Chinese UI language
  //    (like Portuguese, English, Spanish, etc.)
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
