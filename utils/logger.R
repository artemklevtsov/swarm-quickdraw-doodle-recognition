## ---- Загрузка пакетов ----

suppressMessages(library(futile.logger))


## ---- Инициализация логгера

# Формат лога
logger_format <- layout.format("~t [~l]: ~m", "%Y-%m-%d %H:%M:%OS")
# Применение формата лога
invisible(flog.layout(logger_format))
# Перенаправление лога в stdout
invisible(flog.appender(appender.console()))
# Устанавливаем уровень логирования
invisible(flog.threshold(DEBUG))
