# Quick, Draw! Doodle Recognition Challenge

Репозиторий содержит наработки, которые были сделаны в ходе участия в соревновании [Quick, Draw! Doodle Recognition](https://www.kaggle.com/c/quickdraw-doodle-recognition).

## Системные требования

- установленный [Docker](https://docs.docker.com/install/);
- установленный [NVIDIA Container Runtime for Docker](https://github.com/NVIDIA/nvidia-docker);
- (желательно) SSD размером 40G;

## Подготовка

### Сборка docker-образа

Для сборки образа выполните команду:

```bash
docker build --tag doodles-tf .
```

### Получение данных

Войдите в свой аккаунт Kaggle в раздел API и сгенерируйте новый токен (кнопка «Create New API Token»). Полученный файл разместите в корень репозитория или в `${HOME}/.kaggle/kaggle.json`.

Выполните команду:

```bash
KAGGLE_CREDS="${HOME}/.kaggle/kaggle.json"
CMD="./fetch_data.R -o /data -c /kaggle.json"
DATA_DIR="${PWD}/data"
mkdir -p "${DATA_DIR}"
docker run --rm \
           -v "${KAGGLE_CREDS}:/kaggle.json" \
           -v "${DATA_DIR}:/data" \
           doodles-tf ${CMD}
```

Это может занять некоторое время, т.к. данные занимают около 7,5G.

### Загрузка данных в БД

Выполните команду:

```bash
DB_DIR="${PWD}/db"
CMD="./upload_data.R -i /data/train_simplified.zip -d /db"
mkdir -p "${DB_DIR}"
docker run --rm \
           -v "${DATA_DIR}:/data" \
           -v "${DB_DIR}:/db" \
           doodles-tf ${CMD}
```

## Использование

### Обучение модели

Пример кода обучения модели:

```bash
mkdir -p logs
mkdir -p models
SCLAE=0.5
BATCH_SIZE=32
NN_MODEL="mobilenet_v2"
CMD="./train_nn.R -m ${NN_MODEL} -b ${BATCH_SIZE} -c -s ${SCLAE} -d /app/db"
docker run --runtime=nvidia --rm \
           -v "${DB_DIR}:/app/db" \
           -v "${PWD}/logs:/app/logs" \
           -v "${PWD}/models:/app/models" \
           doodles-tf ${CMD}
```

Логи работы и модели находятся в директориях `logs` и `models` соответственно.

### Предсказание

Пример кода для получения предсказаний:

```bash
SCLAE=0.5
BATCH_SIZE=32
MODEL_FILE="${PWD}/models/mobilenet_v2_128_3ch_08_2.26.h5"
CMD="./predict.R -m /app/submit.h5 -b ${BATCH_SIZE} -c -s ${SCLAE} -d /app/db -o /app/data"
docker run --runtime=nvidia --rm \
           -v "${DB_DIR}:/app/db" \
           -v "${DATA_DIR}:/app/data" \
           -v "${MODEL_FILE}:/app/submit.h5" \
           doodles-tf ${CMD}
```
