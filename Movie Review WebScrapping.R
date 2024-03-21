## ----setup, include=FALSE----------------------------------------------------------------------------------------------------
knitr::opts_chunk$set(echo = TRUE)


## ----------------------------------------------------------------------------------------------------------------------------
#install.packages("rvest")
library(rvest)


## ----cars--------------------------------------------------------------------------------------------------------------------
url <- 'https://www.imdb.com/title/tt15239678/reviews?spoiler=hide&sort=curated&dir=desc&ratingFilter=0'


## ----------------------------------------------------------------------------------------------------------------------------
dune_html <- LiveHTML$new(url)


## ----------------------------------------------------------------------------------------------------------------------------
num_clicks <- ceiling(1241 / 25)
num_clicks


## ----------------------------------------------------------------------------------------------------------------------------
# Define a function to click the "load more" button
click_load_more <- function() {
  dune_html$click('#load-more-trigger', n_clicks = 1) 
}

# Use a for loop to click the "load more" button 50 times with a delay of 1 second between clicks
for (i in 1:49) {
  click_load_more()
  Sys.sleep(1)  # Add a 1-second delay after each click
} 


## ----------------------------------------------------------------------------------------------------------------------------
df <- data.frame(rating = character(), review = character(), title = character()
                 , stringsAsFactors = FALSE)


## ----------------------------------------------------------------------------------------------------------------------------
containers <- html_elements(dune_html, xpath = './/div[@class = "lister-item-content"]')
length(containers)


## ----------------------------------------------------------------------------------------------------------------------------
# Get all review elements
reviews <- html_element(containers[1], xpath = './/div[@class = "content"]')
length(reviews)


## ----------------------------------------------------------------------------------------------------------------------------
# Get all rating elements
ratings <- html_element(containers[41], xpath  = './/span[@class="rating-other-user-rating"]')
rating <- html_children(ratings[1])[2] %>% html_text()
length(html_children(ratings))


## ----------------------------------------------------------------------------------------------------------------------------
# Get all titles
titles <- html_elements(dune_html, xpath = '//a[@class = "title"]')
length(titles)


## ----error=TRUE--------------------------------------------------------------------------------------------------------------
for (i in 1:length(containers)) {
  
  # Extract rating
  ratings <- html_element(containers[i], xpath  = './/span[@class="rating-other-user-rating"]')
  if (length(html_children(ratings)) > 0) {
    rating <- html_children(ratings)[2] %>% html_text()
  } else {
    rating <- NA
  }
  
  # Extract title
  title <- html_element(containers[i], xpath = './/a[@class = "title"]') %>% html_text()
  
  # Extract review
  reviews <- html_element(containers[i], xpath = './/div[@class = "content"]')
  review <- html_children(reviews[1])[1] %>% html_text()
  
  # Create a new row dataframe and append to df
  new_row <- data.frame(rating = rating, review = review, title = title, stringsAsFactors = FALSE)
  df <- rbind(df, new_row)
}


## ----------------------------------------------------------------------------------------------------------------------------
# Export DataFrame df to a CSV file
write.csv(df, file = "dune2.csv", row.names = FALSE)


## ----------------------------------------------------------------------------------------------------------------------------
knitr::purl("ReviewScrapping.Rmd", output = "Movie Review WebScrapping.R")

