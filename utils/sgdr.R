SGDR <- R6::R6Class(
    classname = "SGDR",
    inherit = KerasCallback,

    public = list(
        min_lr = NULL,
        max_lr = NULL,
        steps_per_epoch = NULL,
        batch_since_restart = 0,
        next_restart = 0,
        lr_decay = NULL,
        cycle_length = NULL,
        mult_factor = NULL,
        history = NULL,
        best_weights = NULL,

        initialize = function(min_lr,
                              max_lr,
                              steps_per_epoch,
                              lr_decay,
                              cycle_length,
                              mult_factor) {
            self$min_lr <- min_lr
            self$max_lr <- max_lr
            self$lr_decay <- lr_decay
            self$next_restart <- cycle_length
            self$steps_per_epoch <- steps_per_epoch
            self$cycle_length <- cycle_length
            self$mult_factor <- mult_factor
            self$history <- list(lr = NULL)
        },

        clr = function() {
            fraction_to_restart <- self$batch_since_restart / (self$steps_per_epoch * self$cycle_length)
            lr <- self$min_lr + 0.5 * (self$max_lr - self$min_lr) * (1 + cos(fraction_to_restart * pi))
            return(lr)
        },

        on_train_begin = function(logs = NULL) {
            k_set_value(self$model$optimizer$lr, self$max_lr)
        },

        on_batch_end = function(batch, logs = NULL) {
            self$history$lr <- append(self$history$lr, k_get_value(self$model$optimizer$lr))
            self$batch_since_restart <- self$batch_since_restart + 1
            k_set_value(self$model$optimizer$lr, self$clr())
        },

        on_epoch_end = function(epoch, logs = NULL) {
            if (epoch + 1 == self$next_restart) {
                self$batch_since_restart <- 0
                self$cycle_length <- ceiling(self$cycle_length * self$mult_factor)
                self$next_restart <- self$next_restart + self$cycle_length
                self$max_lr <- self$max_lr * self$lr_decay
                self$best_weights <- self$model$get_weights()
            }
        },

        on_train_end = function(logs = NULL) {
            self$model$set_weights(self$best_weights)
        }
    )
)

