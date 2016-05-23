# Identificando testes fracos

Temos alguns testes que nunca quebram. Esses são testes fracos.

A ideia seria capturar builds destes testes que quebram e anotar o status dos testes para saber os que
quebram e os não quebram.

Dessa forma poderíamos ter uma correlação de fraqueza conforme o histórico de
sucesso do testes. Devendo considerar:

* teste nunca quebrou
* correlação de n vezes quebrou vs n vezes sucesso

# Dúvidas?

* devemos considerar testes com histórico mínimo? tipo 5 builds?


# Alterações no projeto

Para fazermos tudo isso funcionar, vamos alterar alguns detalhes aqui.

### Filtro do build status

Hoje o projeto só lida com build de sucess e a busca na API é fixa com `/fixed|sucess/` e não está sendo persistido esse status no banco de dados. então é necessário criar uma coluna status na tabela builds.

    Lembrando que continuamos a ignorar os builds cancelados e pendentes.

### API para fazermos alguma coisa

Tá legal, vamos classificar os testes e vamos ter que fazer algo com isso.

Dessa maneira uma primeira ação seria colocarmos numa cloud com um server para
pelo menos termos uma ideia de como usar em uma aplicação.

Imagina que vamos criar um endpoint como:

    /qa/weak_specs

E esse pode retornar uma lista de specs problemáticos que precisamos filtrar
para não rodar.

Aí no processo de build do CI a gente bate nessa API remota para poder filtrar
quais testes não queremos rodar. Quem sabe podemos cachear isso ou usar tags
como no processo de smoke.





