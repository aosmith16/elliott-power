# Canned power analysis taken from 
        # https://stats.idre.ucla.edu/r/dae/one-way-anova-power-analysis/
groupmeans = c(550, 598, 598, 646)
power.anova.test(groups = length(groupmeans), 
                 between.var = var(groupmeans), 
                 within.var = 6400, 
                 power = 0.8, sig.level = 0.05, n = NULL) 

# Calculate power through simulation as proof of concept
anova_testfun = function(ngroups, n) {
     groups = rep(letters[1:ngroups], times = n)
     y = rnorm(ngroups*n, mean = groupmeans, sd = sqrt(6400) )
     anova(lm(y ~ groups))$`Pr(>F)`[1]
}
anova_testfun(ngroups = 4, n = 17)

allp = replicate(n = 1000, 
                 expr = anova_testfun(ngroups = 4, n = 17),
                 simplify = TRUE)
mean(allp < .05)

# Now make this more specific to current Elliott design

# Vector of names of treatments
trtnames = c("Intensive", "Triad E", "Triad I", "Extensive")
trtn = c(9, 11, 10, 10) # Number per group (same order as names)
groupmeans = c(550, 598, 598, 646) # These means can change
names(groupmeans) = trtnames # Add names to extract largest difference
groupvar = c(6000, 6400, 6400, 6800) # Allow variances to differ per group

# Calculate groups that make up largest and smallest means
# (so biggest difference)
# If have ties, take the first name alphabetically
minmean = names(groupmeans[groupmeans == min(groupmeans)])[1]
maxmean = names(groupmeans[groupmeans == max(groupmeans)])[1]

# Make data
trt = rep(trtnames, times = trtn) # Repeat treatments
# For y to match trt order need to loop through 
# trtn, groupmeans, and groupvar
library(purrr)
# Using unlist() t get in vector
set.seed(16)
y = pmap(list(trtn, groupmeans, groupvar),
         function(n, mean, var) {
              rnorm(n = n, mean = mean, sd = sqrt(var) )
         } ) %>%
     unlist()

# I decided to put these in a data.frame
# to set factor level order
dat = data.frame(trt = forcats::fct_inorder(trt), y)

# Fit model for calculating differences
model = lm(y ~ trt, data = dat)

# But remember are allowing nonconstant variance
# A simple way to get overall test is to use
     # oneway.test for Welch ANOVA
modelw = oneway.test(y ~ trt, data = dat)

# Extract overall F test p-value
anova(model)$`Pr(>F)`[1]
modelw$p.value

# Extract estimated difference for 
     # the two groups that were defined to have largest diff
library(emmeans)
res = as.data.frame( emmeans(model, pairwise ~ trt)$contrasts )
# Get only the row for minmean vs maxmean
res = res[grepl(paste0(minmean, " - ", maxmean), res$contrast) |
               grepl(paste0(maxmean, " - ", minmean), res$contrast),]
res$estimate # I just want the estimate for now

# The emmeans code turned out to be very slow
# Switch to manually pulling out coefficients since
     # I'm only interested in the estimated difference
     # between the min and max defined means right now
coefs = coef(model)
coefs[2:4] = coefs[2:4] + coefs[1]
names(coefs) = groups
est = coefs[maxmean] - coefs[minmean]

# Make a function to return overall p-value and
     # estimate for largest diff
library(purrr)
# I skipped using emmeans because it added
     # a lot of time
anova_fun = function(groups, n, means, vars, maxmean = maxmean, minmean = minmean) {
     trt = rep(groups, times = n)
     y = unlist( pmap(list(n, means, vars),
              function(n, mean, var) {
                   rnorm(n = n, mean = mean, sd = sqrt(var) )
              } ) )
     
     dat = data.frame(trt = forcats::fct_inorder(trt), y)
     model = lm(y ~ trt, data = dat)
     modelw = oneway.test(y ~ trt, data = dat)
     
     coefs = coef(model)
     coefs[2:4] = coefs[2:4] + coefs[1]
     names(coefs) = groups
     est = coefs[maxmean] - coefs[minmean]
     
     results = data.frame(p = modelw$p.value,
                          est)
     names(results) = c("p", paste(maxmean, "minus", minmean) )
     results
}
anova_fun(groups = trtnames,
          n = trtn,
          means = groupmeans,
          vars = groupvar)

allres = replicate(n = 1000, 
                   expr = anova_fun(groups = trtnames,
                                    n = trtn,
                                    means = groupmeans,
                                    vars = groupvar),
                   simplify = FALSE)

allres = do.call("rbind", allres)

# Power
mean(allres$p < .05)

# Distribution of effects

# Calculate true difference based on given means
# I did max minus min throughout function and plot
truediff = groupmeans[maxmean] - groupmeans[minmean]
numsim = 1000

library(ggplot2)
library(ggtext)
ggplot(data = allres, aes(x = .data[[names(allres)[2]]]) ) +
     geom_density(fill = "blue") +
     geom_vline(xintercept = truediff) +
     annotate("label", label = paste("True difference: ", truediff),
              x = truediff, y = 0, angle = 90) +
     labs(title = "Distribution of estimated difference in means",
          subtitle = paste0("*", names(allres)[2], "*"),
          caption = paste("*Results from", numsim, "simulations*"),
          y = "Density",
          x = NULL) +
     theme_bw(base_size = 18) +
     theme(axis.text.y = element_blank(),
           axis.ticks.y = element_blank(),
           plot.caption = element_markdown(),
           plot.subtitle = element_markdown() )

# Add in plot of histogram of p-values
ggplot(data = allres, aes(x = p) ) +
     geom_histogram(fill = "blue", binwidth = .025, boundary = .05) +
     geom_vline(xintercept = 0.05) +
     labs(title = "Distribution of p-values from Welch ANOVA",
          caption = paste("*Results from", numsim, "simulations*"),
          x = "P-value from overall F test",
          y = "Count") +
     scale_x_continuous(breaks = c(0.05, 0.25, 0.50, 0.75, 1.00),
                        expand = expansion(mult = c(0, .05) ) ) +
     scale_y_continuous(expand = expansion(mult = c(0, .02) ) ) +
     theme_bw(base_size = 18) +
     theme(plot.caption = element_markdown() )

# apply() vs pmap(); pmap() seems better
groupdat = data.frame(trtn, groupmeans, groupvar)
set.seed(16)
microbenchmark::microbenchmark( unlist( apply(data.frame(trtn, groupmeans, groupvar), MARGIN = 1, FUN = function(x) {
     rnorm(n = x[1], mean = x[2], sd = sqrt(x[3]) )
} ) ) )

microbenchmark::microbenchmark(unlist(pmap(groupdat,
     function(trtn, groupmeans, groupvar) {
          rnorm(n = trtn, mean = groupmeans, sd = sqrt(groupvar) )
     } ) ) )

microbenchmark::microbenchmark(unlist(pmap(list(trtn, groupmeans, groupvar),
                                           function(trtn, groupmeans, groupvar) {
                                                rnorm(n = trtn, mean = groupmeans, sd = sqrt(groupvar) )
                                           } ) ) )



# Prepare for multiple sample size options ----
trtnames = c("Intensive", "Triad E", "Triad I", "Extensive")
groupmeans = c(550, 598, 598, 646) # These means can change
names(groupmeans) = trtnames # Add names to extract largest difference
groupvar = c(6000, 6400, 6400, 6800) # Allow variances to differ per group

# Calculate groups that make up largest and smallest means
# (so biggest difference)
# If have ties, take the first name alphabetically
minmean = names(groupmeans[groupmeans == min(groupmeans)])[1]
maxmean = names(groupmeans[groupmeans == max(groupmeans)])[1]

# Diff sample sizes
trtn = list(standard = c(9, 11, 10, 10),
            large = c(20, 20, 20, 20) ) # Number per group (same order as names)


# Loop through sample sizes and then replicate each one
    # (make sure run anova_fun code first and load purrr)
multres = map_dfr(trtn, ~do.call("rbind", replicate(n = 1000, 
                     expr = anova_fun(groups = trtnames,
                                      n = .x,
                                      means = groupmeans,
                                      vars = groupvar,
                                      minmean = minmean,
                                      maxmean = maxmean),
                     simplify = FALSE)),
        .id = "sample")


# If do multiple responses (change sample sizes and means)
    # work within lists
# Need to calculate min and max mean group
trtnames = c("Intensive", "Triad E", "Triad I", "Extensive")
params = list(Carbon = list( trtnames = trtnames,
                              trtn = c(9, 11, 10, 10),
                              groupmeans = set_names(c(550, 598, 598, 646), trtnames),
                              groupvar = c(6000, 6400, 6400, 6800)),
             BTYW = list( trtnames = trtnames,
                           trtn = c(20, 20, 20, 20),
                           groupmeans = set_names(c(550, 598, 800, 646), trtnames),
                           groupvar = c(6000, 6400, 6400, 6800))
)

# Calculate min and max group
params = map(params, ~list_modify(.x, 
                                 minmean = names(.x$groupmeans[.x$groupmeans == min(.x$groupmeans)])[1],
                                 maxmean = names(.x$groupmeans[.x$groupmeans == max(.x$groupmeans)])[1]))

# Run through list of lists
# Not sure I like this method as I end up with needing .x$ coding
# Don't bind all with mao_dfr() because could have different 
    # groups that make up largest difference
res_test = map(params, 
        ~do.call("rbind", replicate(n = 100, 
                                   expr = anova_fun(groups = .x$trtnames,
                                                    n = .x$trtn,
                                                    means = .x$groupmeans,
                                                    vars = .x$groupvar,
                                                    minmean = .x$minmean,
                                                    maxmean = .x$maxmean),
                                   simplify = FALSE)),
        .id = "sample")


# Pull out plot code from dashboard for effect size
    # to see how might work with this

# Will need the true difference
truediff = map(params, ~.x$groupmeans[.x$maxmean] - .x$groupmeans[.x$minmean])
n = 100 # Sims size; will probably set earlier for actual runs

# Testing for how will go in powerpoint
library(ggplot2)
library(ggtex)

ggplot(data = res_test[[1]], aes(x = .data[[names(res_test[[1]])[2]]]) ) +
        geom_density(fill = "blue", alpha = .5) +
        geom_vline(xintercept = truediff[[1]], size = 0.75) +
        annotate("label", label = paste("True difference:", truediff[[1]]),
                 x = truediff[[1]], y = 0, angle = 90, size = 4) +
        labs(title = names(res_test)[[1]],
             subtitle = paste0("Distribution of largest estimated difference in means,<br>",
                               "<span>&nbsp;</span><span>&nbsp;</span><span>&nbsp;</span><span>&nbsp;</span>", 
                               names(res_test[[1]])[2]),
             caption = paste("*Results from", n, "simulations.<br>
                             Vertical line shows true difference calculated from Woodstock.*"),
             y = "Density",
             x = NULL) +
        theme_bw(base_size = 12) +
        theme(axis.text.y = element_blank(),
              axis.ticks.y = element_blank(),
              plot.caption = element_markdown(),
              plot.subtitle = element_markdown(margin = unit(c(0, 0, 0, 0), "pt")),
              plot.title = element_text(face = "bold", margin = unit(c(0, 0, 0, 0), "pt")),
              panel.grid.minor.y = element_blank(),
              panel.grid.major.y = element_blank() )

# Test size for powerpoint
# Do 150 dpi so even if make twice as big still have ~72 dpi
    # (most screens max at 72 dpi)
ggsave(
    "test.png", 
    plot = last_plot(),
    width = 5, height = 4, units = "in", dpi = 150
)
