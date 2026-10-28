# dev vs prod — toda diferença de configuração

Princípio geral: **dev otimiza custo e velocidade de iteração; prod otimiza segurança e alta
disponibilidade.** Cada linha abaixo é uma decisão deliberada, não uma inconsistência.

| Configuração | dev | prod | Por quê |
|---|---|---|---|
| CIDR da VPC | `10.0.0.0/16` | `10.1.0.0/16` | Evita sobreposição se um dia precisar de VPC peering entre ambientes |
| NAT Gateway | 1 compartilhado | 1 por AZ | Prod não pode ter ponto único de falha na saída de internet das tasks |
| RDS Multi-AZ | não | sim | Failover automático só importa em prod |
| ElastiCache Multi-AZ | não (1 nó) | sim (2 nós) | Mesma lógica |
| RDS deletion protection | `false` | `false` **por enquanto** | Fase atual do projeto exige sobe-e-derruba completo dos dois ambientes; ligar em prod no go-live (item de checklist) |
| ALB deletion protection | `false` | `false` **por enquanto** | Mesma lógica — ligar no go-live |
| ECS `desired_count` inicial | 1 | 2 | Autoscaling ligado nos dois ambientes (min/max abaixo) |
| Autoscaling `min_capacity`/`max_capacity` | 1 / 4 | 2 / 8 | Prod nunca cai pra zero capacidade de baseline |
| Autoscaling `cpu_target_value` | 70% | 60% | Prod escala mais cedo, com mais folga antes de saturar |
| CodeDeploy traffic shifting | `ECSAllAtOnce` | `ECSCanary10Percent5Minutes` | Prod migra 10% do tráfego primeiro, testa 5 min, só depois migra o resto — dev prioriza velocidade |
| WAF | não | sim (ALB + CloudFront/Amplify) | Custo — dev não precisa de proteção L7 de produção |
| Backup cross-region do RDS | não | sim (us-west-2) | Só prod justifica o custo de DR |
| Backup retention do RDS | 7 dias | 7 dias | Igual nos dois |

## O que é igual nos dois ambientes

- Alarmes CloudWatch (mesma cobertura, thresholds absolutos iguais — exceto onde a tabela acima
  já diferencia)
- Container Insights, Performance Insights
- Criptografia (RDS, ElastiCache)
- `auto_minor_version_upgrade = false` no RDS
- Estrutura de módulos e stacks (mesmo código, valores de variável diferentes)
- Permission boundary na role `iac`

## Domínio

| Ambiente | Domínio | Tipo de zone |
|---|---|---|
| dev | `dev.4o4.com.br` | Subdomínio delegado (registro NS na zone de prod) |
| prod | `4o4.com.br` | Zone apex — raiz do domínio, nameservers precisam estar no registrador |
