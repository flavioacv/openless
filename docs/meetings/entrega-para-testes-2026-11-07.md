# Entrega do Meeting para testes — 07/11/2026

> Registro histórico. As correções e evidências mais recentes estão na [entrega de 08/11](correcoes-finais-2026-11-08.md).

## Integração atual

Gravação de aplicação + microfone e de reunião presencial; importação de áudio/vídeo; transcrição final com tempos e falantes; edição/união de falantes; resumos, decisões e tarefas por canal de IA; exportação e recuperação estão ligados à tela e ao host Tauri. As operações finais são solicitadas pelos botões, preservando o áudio independentemente da disponibilidade da IA.

Português está disponível na transcrição final local (Parakeet v3 + Nemotron) e via ElevenLabs. O resumo pede o idioma da transcrição. As legendas durante a gravação também aceitam português com Parakeet v3: janela máxima de 12 segundos, atualização a cada três segundos de áudio, um segundo provisório e deduplicação de palavras cujo tempo foi reajustado pelo reconhecedor. Espanhol/francês/alemão usam o mesmo caminho; inglês mantém EOU. Legendas exigem Apple Silicon com pelo menos 8 GB. A identificação final de falantes continua separada dos rascunhos ao vivo.

AEC3 usa o componente real da referência no macOS 15+, com entrada de microfone e aplicação no mesmo relógio. O macOS 14 mantém captura sem AEC. O áudio bruto é preservado e a análise usa a trilha tratada somente quando cobre o áudio original completo.

## Evidências

| Verificação | Resultado |
| --- | --- |
| Modelos reais | Parakeet: 483.258.971 bytes; Nemotron: 199.265.487; EOU: 224.052.248. Todos os arquivos conferidos com hashes das revisões fixadas |
| Transcrição final em português + diarização | Passou com áudio público e modelos reais; retornou palavras temporizadas e atribuição de voz |
| Legendas em português | Passou com o mesmo áudio e Parakeet real, sem depender do modelo EOU inglês |
| XCTest | Nove passaram, sem ignorados na execução com os pesos: alinhamento de voz, modelos, AEC real, memória/tempo/deduplicação de legendas e os dois fluxos de inferência real |
| Core | 32 testes passaram no último conjunto de regressão, sem alterações posteriores na lógica core |
| Áudio | Quatro testes WAV passaram, incluindo entrada inválida, preservação do original, blocos de 60 s e 8 kHz sem lacunas artificiais |
| AEC | Regressão upstream por biblioteca dinâmica real passou: reset, eco e fala simultânea, incluindo voz próxima fraca |
| Interface | TypeScript, build frontend e formatação aprovados |
| Host | `cargo check` e `cargo build` completos passaram, com os avisos existentes de dependências/FFI e rpath duplicado |
| Vídeo | MOV real com vídeo + áudio foi produzido com ffmpeg já instalado; o decoder AVFoundation retornou -11800 com erro subjacente -1 no ambiente restrito. Esse teste não foi contado como aprovado |

O áudio de validação veio de [PolyAI/minds14, configuração pt-PT](https://huggingface.co/datasets/PolyAI/minds14). Duas amostras foram importadas pelo decoder real, normalizadas e combinadas em uma fixture de cerca de 29 segundos. É uma verificação de integração em português; não substitui avaliação de precisão numa reunião, nem comparação de desempenho com o FluidVoice. Não houve chamada a uma API paga.

O teste com áudio de 8 kHz revelou uma falha corrigida nesta entrega: o conversor retinha frames entre callbacks e o código ancorava a saída no próximo tempo de entrada, criando lacunas falsas. A continuidade agora acompanha os tempos da entrada e o número de frames efetivamente escritos, incluindo o esvaziamento final do conversor.

## Build desta sessão

O sandbox interno do SwiftPM não funciona dentro do ambiente restrito do agente. O build completo usou fontes reais das dependências fixadas, preparadas localmente, e uma pasta temporária gravável. Os padrões de produção permanecem o pacote Swift remoto e seus pins. As opções de desenvolvimento adicionadas ao build são:

- `OPENLESS_MEETING_SWIFT_PACKAGE`: pacote de fontes local para desenvolvimento offline; não injeta uma biblioteca pré-compilada.
- `OPENLESS_MEETING_SWIFT_SCRATCH`: diretório de intermediários e caches Swift.
- `OPENLESS_SWIFTPM_DISABLE_SANDBOX=1`: desativa somente o sandbox interno do SwiftPM; as permissões do processo continuam valendo.
- `OPENLESS_SWIFTPM_BUILD_SYSTEM`: opção explícita do sistema de build; normalmente não é necessária.

O Core ML precisou de `TMPDIR` apontando para um subdiretório gravável (`/private/tmp/openless-coreml-work/`) para compilar Nemotron. Essa configuração foi usada no teste; não foi alterada globalmente na máquina.

O download de validação usou HTTPS pelo terminal. A instalação foi registrada no mesmo formato privado que o aplicativo valida, após conferir todos os hashes. O download através do URLSession dentro do aplicativo ainda precisa de teste fora das restrições de rede do agente.

## Executar

Aplicativo gerado: [OpenLess.app](../../openless-all/app/src-tauri/target/debug/bundle/macos/OpenLess.app), com aproximadamente 234 MiB. É uma build de teste para Apple Silicon, com assinatura ad hoc local verificada por `codesign --verify --deep --strict`; não é uma distribuição notarizada. Foram conferidos o executável principal, a cápsula nativa, a biblioteca AEC3, os recursos Swift Hub/Crypto, as licenças e os arquivos de permissões em português. O destino mínimo continua macOS 14; AEC3 é carregado somente no macOS 15+.

```sh
open "/Volumes/Externo 1/projetos/zurc/openless/openless-all/app/src-tauri/target/debug/bundle/macos/OpenLess.app"
```

Siga o [roteiro completo](como-testar.md). Para desenvolvimento, em `openless-all/app`: `npm run tauri -- dev`. O navegador com apenas Vite não executa o módulo nativo.

Saia completamente da versão antiga antes de abrir a nova cópia: a proteção contra múltiplas instâncias pode apenas trazer a janela antiga para frente. Na tela, selecione **Português**, idioma falado **Português (Brasil)** e baixe Parakeet/Nemotron. Para legendas em português, basta Parakeet; EOU é necessário para legendas em inglês. Selecione o canal Gemini já configurado para os resumos.

Os pesos usados no teste estão temporariamente em `/private/tmp/openless-real-meeting-models/{parakeet,nemotron,live}`. Para reaproveitá-los, com o aplicativo fechado, copie os diretórios desejados para `~/Library/Application Support/OpenLess/meeting-models/`, preservando seus arquivos `installed.json`. Não substitua modelos enquanto estiverem sendo usados. Essa cópia é opcional; o fluxo normal é baixar pela tela.

## Repetir verificações nativas

Em `openless-all/app`, `python3 scripts/test-meeting-media.py` executa os quatro testes de áudio; o vídeo é explícito por exigir os serviços de mídia do macOS e ffmpeg já instalado: `OPENLESS_MEETING_TEST_VIDEO=1 python3 scripts/test-meeting-media.py`. A falha encontrada no agente permanece registrada, sem alterar o teste para aceitá-la.

Depois de compilar o runtime e preparar o AEC, `xcrun swift test --package-path src-tauri` executa as verificações nativas sem pesos. Para os dois testes de inferência real, defina `OPENLESS_MEETING_SMOKE_AUDIO` (WAV PCM16 mono 16 kHz) e `OPENLESS_MEETING_SMOKE_MODELS` (pasta dos modelos instalados). Sem essas variáveis, somente esses dois testes são ignorados; não contar isso como validação dos modelos.

## Aceite no Mac do usuário

Confirmar permissões, captura de microfone/aplicação, legendas durante captura, troca de dispositivos, qualidade do eco, codecs de vídeo e chamada ao canal Gemini/ElevenLabs. Esses testes dependem dos dispositivos, permissões e credenciais do usuário. Não foram substituídos por mocks nem declarados aprovados sem execução.
