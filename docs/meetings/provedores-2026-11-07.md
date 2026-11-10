# Seleção de provedores do Meeting — 07/11/2026

## Implementado

O Meeting agora permite escolher um canal ativo para transcrição/falantes e outro para resumos/decisões/tarefas. As opções exibem o nome e o modelo configurado. Sem seleção específica, é usado o canal geral atual da respectiva etapa.

O backend resolve as credenciais de uma cópia privada da configuração, em uma leitura consistente do cofre. Não salva mudanças no canal ativo do ditado, não reordena canais e rejeita canais inexistentes/desativados. A listagem retorna somente ID, nome, provedor e modelo; chaves, endpoints e cabeçalhos não chegam à tela por esse comando.

Transcrição com falantes continua usando ElevenLabs. Para resumos, Gemini agora usa `GeminiProvider` com `generateContent`, `x-goog-api-key`, instrução própria de reunião e saída JSON. O caminho anterior aplicava o transporte compatível com OpenAI a todos os provedores e não atendia corretamente o canal nativo Gemini. Cabeçalhos extras configurados no canal são preservados. Outros canais por API continuam no transporte compatível com o protocolo selecionado.

Os resumos continuam vinculados à revisão da transcrição e validam referências a segmentos, sem inventar responsáveis ou prazos. O provedor/modelo usados ficam no resultado salvo.

## Modelos locais

Parakeet TDT v3 (transcrição) e Nemotron 3 (diarização) são públicos. O runtime Swift/CoreML FluidAudio também é público. Ainda não foram adicionados como dependência nem baixados. A autorização explícita para adicionar FluidAudio foi solicitada conforme a regra de dependências do AGENTS.md; não houve resposta até este registro.

A combinação prevista permite transcrição/falantes locais e resumo pelo Gemini configurado. Resumos totalmente locais precisam de um LLM local separado. Fluid Intelligence privado não é requisito dessa proposta. Não há botão de download simulando uma integração ainda ausente.

Referências: [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Nemotron CoreML](https://huggingface.co/altic-dev/nemotron-3-diarization-coreml), [FluidAudio](https://github.com/altic-dev/FluidAudio). O modelo Gemini de linguagem usado em resumos e um modelo especializado em transcrição são capacidades diferentes; selecionar um canal não garante que ele forneça falantes/tempos.

## Validação e limites

- 28 testes de documentos/processamento/contrato do core reaprovados.
- 17 testes do módulo Gemini aprovados, incluindo construção da requisição nativa de reunião sem conexão de rede.
- TypeScript, build frontend e formatação dos arquivos TS/TSX aprovados.
- Host Rust verificado sem erros usando artefatos locais. Não equivale ao build/link/empacotamento completo do aplicativo.
- O teste HTTP local `meeting_providers` tentou abrir uma porta de loopback e foi bloqueado por `Operation not permitted`. Ficou como teste explícito (`--ignored`), sem ser contabilizado como aprovado.
- Dois testes de seleção/isolamento de canais foram adicionados ao host; ainda não executados no ambiente com build Tauri completo.
- Não houve chamada ao Gemini/ElevenLabs com chave real, gravação de reunião real, teste visual ou geração de nova versão instalada.

Em um terminal com permissão de loopback, o teste HTTP pode ser executado a partir de `openless-all/app` com:

```sh
cargo test --offline -p openless-core --test meeting_providers -- --ignored
```

O [roteiro de teste](como-testar.md) descreve os passos reais da interface. Gravação suporta a aplicação selecionada mais microfone, ou somente microfone no modo presencial. Transcrição e resumo são solicitados depois da captura; não há legendas ao vivo nesta implementação.
