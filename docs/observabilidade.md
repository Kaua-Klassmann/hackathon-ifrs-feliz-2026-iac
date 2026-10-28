# Observabilidade — alarmes, dashboard, notificação

## Canal de notificação

Um tópico SNS por ambiente (`{env}/alerting`, stack independente, sem dependência de nenhum
outro), assinatura de email. **A AWS manda um email de confirmação depois do apply — os
alarmes não entregam nada até alguém clicar "Confirm subscription".** Telegram foi considerado
(precisaria de uma Lambda própria + Secrets Manager pro token do bot — sem integração nativa da
AWS como existe pra Slack) e ficou de fora por enquanto, registrado como possível evolução
futura.

## Alarmes — cobertura completa

Todos opt-in via `sns_topic_arn` (variável nula por padrão em cada módulo — só cria alarme se o
stack passar o ARN do tópico).

| Recurso | Alarme | Condição | Namespace/métrica |
|---|---|---|---|
| ECS | Tasks rodando abaixo do piso | `RunningTaskCount` < `min_capacity` (ou `desired_count` sem autoscaling) por 2 min | `ECS/ContainerInsights` |
| ECS | CPU alto | > 85% sustentado por 10 min | `AWS/ECS` `CPUUtilization` (separado do alarme de autoscaling, que só escala) |
| ALB | Taxa de erro 5xx | > 5% dos requests em 5 min | metric math: `HTTPCode_Target_5XX_Count` / `RequestCount`, dimensão só `LoadBalancer` |
| ALB | Latência p99 | > 1s sustentado por 5 min | `TargetResponseTime`, combinado blue+green via `MAX()` |
| ALB | Hosts não saudáveis | > 0 por 2 min | `UnHealthyHostCount`, combinado blue+green via `MAX()` |
| RDS | Espaço livre baixo | < 10% do storage alocado | `FreeStorageSpace` — o mais crítico da lista, disco cheio derruba o banco inteiro |
| RDS | CPU alto | > 80% sustentado por 10 min | `CPUUtilization` |
| RDS | Conexões no limite | > 90 (≈80% do teto de `db.t4g.micro`, ajustar se `instance_class` mudar) | `DatabaseConnections` |
| RDS | Memória livre baixa | sustentado baixo | `FreeableMemory` |
| RDS | Eventos nativos | failover, falha, pouco espaço, manutenção | `aws_db_instance_event_subscription`, mecanismo separado de métrica |
| ElastiCache | CPU alto | > 75% sustentado | `CPUUtilization` (não `EngineCPUUtilization` — recomendação da AWS pra nós com 2 vCPUs ou menos, caso do `cache.t4g.micro`) |
| ElastiCache | Evictions | > 0 sustentado | `Evictions` — sinal de cache subdimensionado |

Thresholds são pontos de partida sensatos, não valores fixos publicados pela AWS — ajustar
depois de tráfego real em produção (mesma lógica já usada pro `cpu_target_value` do
autoscaling).

### Container Insights — pré-requisito descoberto durante a implementação

`RunningTaskCount` não é publicado por padrão no Fargate — o namespace `AWS/ECS` só publica
CPU/memória sem Container Insights habilitado. `container_insights = true` (default no
`modules/ecs-service`) é o que faz esse alarme funcionar.

## Dashboard

Um `aws_cloudwatch_dashboard` por ambiente (`hackathon-{env}-overview`), criado dentro do stack
`compute` (não um stack próprio — ver [`stacks-e-modulos.md`](./stacks-e-modulos.md) pro porquê
de não ser um stack `monitoring` central). Layout agrupado por recurso, na ordem em que
normalmente se investiga um incidente — borda primeiro, dados por último:

1. **ALB** — taxa de erro 5xx, latência p99 (blue vs green lado a lado, não combinado — ver o
   cutover acontecendo é informação útil aqui), hosts saudáveis vs total (blue + green)
2. **ECS** — CPU do serviço, memória do serviço, tasks rodando vs. desejado
3. **RDS** — CPU, espaço livre, conexões, memória livre
4. **ElastiCache** — CPU, evictions

## Performance Insights (RDS)

Habilitado por padrão, retenção de 7 dias (gratuita nesse nível, sem custo adicional).

## Custos a saber

- Container Insights: pequeno custo adicional de CloudWatch (métricas granulares por task).
- Alarmes CloudWatch: custo por alarme/mês, baixo.
- WAF (ver [`seguranca.md`](./seguranca.md)): não é observabilidade, mas também gera métricas
  CloudWatch por regra (`sampled_requests_enabled` em cada uma).
