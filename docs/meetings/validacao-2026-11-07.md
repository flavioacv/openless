# Validação da primeira etapa — 07/11/2026

> Registro histórico. As correções e evidências mais recentes estão na [entrega de 08/11](correcoes-finais-2026-11-08.md).

Branch: `feat/meeting-recording`.

| Verificação | Resultado |
| --- | --- |
| `cargo test --offline -p openless-core --test meeting_documents` | 13 testes aprovados |
| `cargo test --offline -p openless-core --test contract_2` | 6 testes existentes aprovados |
| `git diff --check` | Sem problemas |

Comandos Cargo executados em `openless-all/app`, acompanhados pelo wrapper `orkest telemetry` (execuções `r_3` e `r_4`). Esses IDs são da execução atual do Orkest. As dependências já declaradas e travadas no repositório foram baixadas após a primeira tentativa offline encontrar cache incompleto; não houve alteração de manifests ou lockfile.

O componente `rustfmt` não está instalado no toolchain disponível. Não foi instalado tooling adicional; a formatação foi ajustada manualmente. A validação acima não equivale a `cargo fmt --check`.

O escopo testado é o documento persistido de reunião e a preservação do contrato público existente. A captura nativa, o ASR/diarização, o decoder de mídia, a geração por IA, os comandos IPC e as telas ainda não estão conectados. Não houve teste com áudio real, build do aplicativo desktop ou medição de qualidade/latência em português.
