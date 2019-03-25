# Quick, Draw! Doodle Recognition Challenge

Репозиторий содержит наработки, которые были сделаны в ходе участия в соревновании [Quick, Draw! Doodle Recognition](https://www.kaggle.com/c/quickdraw-doodle-recognition).

## Структура репозитория

- `Dockerfile` - докер-образ со всем необходимым для тренирови моделей;
- `src` - директория содержит C++ код;
- `src/cv_xt.cpp` - иходный код для работы с JSON и формирования на их основе батчей;
- `utils` - директория содержит вспомогательные функции для R-скриптов;
- `utils/get_model.R` - функция для получения объекта модели, по её краткому названию;
- `utils/keras_iterator_test.R` - код итератора для тестовых данных;
- `utils/keras_iterator.R` - код итератора для обучения;
- `utils/rcpp.R` - плагины для Rcpp;
- `bin` - директория содержит исплдгяемые скрипты;
- `bin/fetch_data.R` - скрипт для скачивания данных с сайта Kaggle;
- `bin/upload_data.R` - скрипт для загрузки данных в БД;
- `bin/train_nn.R` - скрипт для тренировки нейронных сетей;
- `bin/predict.R` - скрипт для формирования файла с предсказаниями;

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

### Параметры и ФС

Выполнить в терминале (bash):

```bash
# Директории
DATA_DIR="${PWD}/data"
DB_DIR="${PWD}/db"
LOGS_DIR="${PWD}/logs"
MODELS_DIR="${PWD}/odels"

# Параметры скриптов
SCLAE=0.5
BATCH_SIZE=32
NN_MODEL="mobilenet_v2"

# Создаём необходимые директории
mkdir -p "${DATA_DIR}"
mkdir -p "${DB_DIR}"
mkdir -p "${LOGS_DIR}"
mkdir -p "${MODELS_DIR}"
```

### Получение данных

Войдите в свой аккаунт Kaggle в раздел API и сгенерируйте новый токен (кнопка «Create New API Token»). Полученный файл разместите в корень репозитория или в `${HOME}/.kaggle/kaggle.json`.

Выполните команду:

```bash
KAGGLE_CREDS="${HOME}/.kaggle/kaggle.json"
CMD="./fetch_data.R -o /data -c /kaggle.json"
docker run --rm \
           -v "${KAGGLE_CREDS}:/kaggle.json" \
           -v "${DATA_DIR}:/data" \
           doodles-tf ${CMD}
```

Это может занять некоторое время, т.к. данные занимают около 7,5G.

### Загрузка данных в БД

Выполните команду:

```bash
CMD="./upload_data.R -i /data/train_simplified.zip -d /db"
docker run --rm \
           -v "${DATA_DIR}:/data" \
           -v "${DB_DIR}:/db" \
           doodles-tf ${CMD}
```

## Использование

### Обучение модели

Пример кода обучения модели:

```bash
CMD="./train_nn.R -m ${NN_MODEL} -b ${BATCH_SIZE} -c -s ${SCLAE} -d /app/db"
docker run --runtime=nvidia --rm \
           -v "${DB_DIR}:/app/db" \
           -v "${LOGS_DIR}:/app/logs" \
           -v "${MODELS_DIR}:/app/models" \
           doodles-tf ${CMD}
```

Логи работы и модели находятся в директориях `logs` и `models` соответственно.

### Предсказание

Пример кода для получения предсказаний:

```bash
MODEL_FILE="${MODELS_DIR}/mobilenet_v2_128_3ch_08_2.26.h5"
CMD="./predict.R -m /app/submit.h5 -b ${BATCH_SIZE} -c -s ${SCLAE} -d /app/db -o /app/data"
docker run --runtime=nvidia --rm \
           -v "${DB_DIR}:/app/db" \
           -v "${DATA_DIR}:/app/data" \
           -v "${MODEL_FILE}:/app/submit.h5" \
           doodles-tf ${CMD}
```
