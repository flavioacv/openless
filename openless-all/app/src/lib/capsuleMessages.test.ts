import { translateCapsuleMessage } from './capsuleMessages';

function assertEqual<T>(actual: T, expected: T, message?: string) {
  if (actual !== expected) {
    throw new Error(
      `${message ?? 'Assertion failed'}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

const dictionary: Record<string, string> = {
  'capsule.error': 'Algo deu errado',
  'capsule.cancelled': 'Cancelado',
  'capsule.inserted': '{{count}} inseridos',
  'capsule.insertedDone': 'Inserido',
  'capsule.pasteSent': 'Colar enviado, confirme',
  'capsule.copiedFallback': 'Copiado, cole manualmente',
  'capsule.processedDone': 'Concluído',
  'capsule.preparingVoice': 'Preparando voz…',
  'capsule.downloadingModel': 'Baixando modelo CPU, o primeiro uso pode ser mais lento…',
  'capsule.selectionPolish.polishing': 'Aprimorando…',
  'capsule.selectionPolish.replaced': 'Substituído',
  'capsule.selectionPolish.noSelection': 'Nada selecionado',
  'capsule.selectionPolish.failed': 'Falha ao aprimorar, tente novamente',
  'capsule.errors.permissionDenied': 'Permita o acesso ao microfone e tente novamente',
  'capsule.errors.busy': 'Outra tarefa de voz está em andamento',
  'capsule.errors.providerOrNetwork': 'Falha no reconhecimento ou aprimoramento, tente novamente',
  'capsule.errors.platformError': 'Falha na gravação ou entrada de texto, tente novamente',
  'capsule.errors.invalidArgument': 'Entrada ou configuração inválida, verifique e tente novamente',
  'capsule.errors.invalidState': 'O estado atual não permite esta operação, tente novamente',
  'capsule.errors.unsupported': 'A configuração ou plataforma atual não suporta esta operação',
  'capsule.errors.persistenceError':
    'Falha ao salvar o resultado, verifique o disco e tente novamente',
  'capsule.errors.outcomeUnknown': 'Não foi possível confirmar a inserção, verifique o aplicativo',
  'capsule.errors.internalError': 'Erro interno no processamento, tente novamente',
  'capsule.errors.genericError': 'Falha no processamento, tente novamente',
  'capsule.errors.qaError': 'Falha no processamento do assistente, tente novamente',
};

const createMockT = (lng = 'pt') => {
  const fn = (key: string, options?: { count?: number; defaultValue?: string }) => {
    let val = dictionary[key] ?? options?.defaultValue ?? key;
    if (options?.count !== undefined) {
      val = val.replace('{{count}}', String(options.count));
    }
    return val;
  };
  (fn as unknown as { lng: string }).lng = lng;
  return fn as unknown as Parameters<typeof translateCapsuleMessage>[1];
};

// 1. Chinese errors from backend
const t = createMockT('pt');
assertEqual(
  translateCapsuleMessage('请允许麦克风权限后重试', t, 'error'),
  'Permita o acesso ao microfone e tente novamente',
);
assertEqual(
  translateCapsuleMessage('另一个语音任务正在进行', t, 'error'),
  'Outra tarefa de voz está em andamento',
);
assertEqual(
  translateCapsuleMessage('识别或润色失败，请重试', t, 'error'),
  'Falha no reconhecimento ou aprimoramento, tente novamente',
);
assertEqual(
  translateCapsuleMessage('录音或输入失败，请重试', t, 'error'),
  'Falha na gravação ou entrada de texto, tente novamente',
);

// 2. Error codes
assertEqual(
  translateCapsuleMessage('PermissionDenied', t, 'error'),
  'Permita o acesso ao microfone e tente novamente',
);
assertEqual(translateCapsuleMessage('Busy', t, 'error'), 'Outra tarefa de voz está em andamento');
assertEqual(
  translateCapsuleMessage('Network', t, 'error'),
  'Falha no reconhecimento ou aprimoramento, tente novamente',
);
assertEqual(
  translateCapsuleMessage('Timeout', t, 'error'),
  'Falha no reconhecimento ou aprimoramento, tente novamente',
);

// 3. Completion and fallback messages
assertEqual(translateCapsuleMessage('已输入', t, 'done'), 'Inserido');
assertEqual(translateCapsuleMessage('Inserted', t, 'done'), 'Inserido');
assertEqual(translateCapsuleMessage('已发送粘贴，请确认', t, 'done'), 'Colar enviado, confirme');
assertEqual(translateCapsuleMessage('已复制，请手动粘贴', t, 'done'), 'Copiado, cole manualmente');
assertEqual(translateCapsuleMessage('CopiedFallback', t, 'done'), 'Copiado, cole manualmente');
assertEqual(translateCapsuleMessage('已插入 12', t, 'done'), '12 inseridos');

// 4. Preparation and notices
assertEqual(translateCapsuleMessage('正在准备语音…', t, 'recording'), 'Preparando voz…');
assertEqual(
  translateCapsuleMessage('正在下载 CPU 模型，首次使用可能较慢…', t, 'transcribing'),
  'Baixando modelo CPU, o primeiro uso pode ser mais lento…',
);
assertEqual(
  translateCapsuleMessage('润色失败，请重试', t, 'error'),
  'Falha ao aprimorar, tente novamente',
);

// 5. Fallback on error without message
assertEqual(translateCapsuleMessage(undefined, t, 'error'), 'Algo deu errado');
assertEqual(translateCapsuleMessage('', t, 'error'), 'Algo deu errado');
assertEqual(translateCapsuleMessage(undefined, t, 'done'), undefined);

// 6. Unknown Chinese text in non-Chinese locale during error
assertEqual(
  translateCapsuleMessage('未知中文错误信息', t, 'error'),
  'Falha no processamento, tente novamente',
);

console.log('All capsule translation unit tests passed successfully!');
