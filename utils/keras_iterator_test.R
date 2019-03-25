test_generator <- function(dt,
                           batch_size = 32,
                           scale = 1,
                           color = FALSE,
                           imagenet_preproc = FALSE) {
    # Проверка аргументов
    checkmate::assert_data_table(dt)
    checkmate::assert_count(batch_size)
    checkmate::assert_number(scale, lower = 0.001, upper = 5)
    checkmate::assert_flag(color)
    checkmate::assert_flag(imagenet_preproc)

    # Проставляем номера батчей
    dt[, batch := (.I - 1L) %/% batch_size + 1L]
    data.table::setkey(dt, batch)
    i <- 1

    function() {
        # Парсинг JSON и подготовка массива
        batch_x <- cpp_process_json_vector(dt[batch == i, drawing], scale = scale, color = color)
        if (imagenet_preproc) {
            # Шкалирование c интервала [0, 1] на интервал [-1, 1]
            batch_x <- (batch_x - 0.5) * 2
        }

        # Увеличиваем счётчик
        i <<- i + 1

        result <- list(batch_x)
        return(result)
    }
}
