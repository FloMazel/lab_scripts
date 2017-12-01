#basic procedure for loading in a .biom file, processing data with phyloseq, doing diversity analyses

#### load libraries ####
#you must install these first if you want to load the data in using phyloseq and process with deseq
library(tidyverse)
# Load the reshape2 package for converting between long and wide format data
library(reshape2)
# Load the stringr package for improved filtering of text
library(stringr)
# Load the ape package for reading and modifying phylogenetic trees
library(ape)
# Load the phyloseq package for microbial community analysis
library(phyloseq)
# Load the data.table package for better metadata manipulation
library(data.table)
# Load the viridis package for colour palettes for continuous data
library(viridis)
# Load the qualpalr package for colour palettes for qualitative data
library(qualpalr)
# load the ggplot2 package for visualization of data
library(ggplot2)
#load the vegan library
library(vegan)

#### environment settings ####
#set working directory
setwd("/path/to/working/directory/")

#### load in .biom file, metadata, and (optional) phylogenetic tree ####
# REQUIRED: Read the raw data in .biom format, and store as a phylo_seq object called "rawdata"
rawdata <- import_biom(file.path("/file/path/", "OTU_Table.biom"), # file.path() is used for cross-platform compatibility
                       parallel = TRUE,
                       trim_ws = TRUE) # use multiple processor cores for shorter read times

# REQUIRED: Read the raw metadata in .txt format, and store as a tibble (an improved dataframe) called "rawmetadata"
rawmetadata <- read_delim(file = file.path("/file/path/", "metadata.txt"), # file.path() is used for cross-platform compatibility
                          "\t", # the metadata file must be tab delimited and in .txt format
                          escape_double = FALSE, # the imported text file does not 'escape' quotation marks by wrapping them with more quotation marks
                          trim_ws = TRUE) # remove leading and trailing spaces from character string entries

# OPTIONAL: Read in a phylogenetic tree in .tre format, and store as a tree object called "rawtreedata"
# IMPORTANT: TREE TIPS MUST MATCH OTU IDs FROM TAXA TABLE. THIS MEANS IF YOU ARE USING AN EPA PLACEMENT TREE, YOU MUST REMOVE "QUERY___" from each tree tip label BEFORE IMPORTING if you wish to use the tree in a phyloseq object
# file.path() is used for cross-platform compatibility
rawtreedata <- read_tree(file.path("/file/path", "phylo_tree.tre"))

#IMPORTANT NOTE: at this point you should make sure your sample IDs in the data, metadata, and tree data objects match

#### OPTIONAL: drop unwanted levels from metadata now, before converting to phyloseq ####
rawmetadata <- rawmetadata[which(rawmetadata$variable != "value"), ] #works with factor-formatted or continuous variables
#### create phyloseq object with completed metadata, otu table, and tree ####
project_data <- merge_phyloseq(data, metadata, rawtreedata)
#filtering steps, if not already done before loading into R
#filter out samples with less than 1000 reads (arbitrary threshold, choose your own)
project_data <- prune_samples(sample_sums(project_data) >= 1000, project_data) 
# Remove OTUs with less than N total reads. (N = 250 in example) 
project_data <- prune_taxa(taxa_sums(project_data) >= 250, project_data)
# Remove mitochondrial and chloroplast OTUs #IMPORTANT: make sure that the filter terms will work with your taxonomy strings, and ranks
project_data <- project_data %>%
  subset_taxa(Rank5 != "__Mitochondria") %>% 
  subset_taxa(Rank3 != "__Chloroplast")
# OPTIONAL: modify Rank labels in taxa table (check the colnames of the tax_table(project_data) object to see if you want to change them)
colnames(tax_table(project_data)) <- c("Rank1", "Rank2", "Rank3", "Rank4", "Rank5", "Rank6", "Rank7")

#### plot rarefaction curves ####
plot(sort(sample_sums(project_data))) #looking at sample read counts
summary(sample_sums(project_data))

#found rarefaction curve function here: https://github.com/mahendra-mariadassou/phyloseq-extended (richness.R) 
#to use this you have to load the "ggrare" function in from richness.R #it will throw errors if you are labeling with groups that have too few categories
p <- ggrare(project_data, step = 1000, color = "factor", se = FALSE)
p + facet_wrap(~factor1 + factor2)
#you can use the plot above to judge a rough cutoff for rarefaction. you can also do this with QIIME's alpha rarefaction script

#you can use which like the example below to see which samples you'll lose for a given cutoff value
which(sample_sums(project_data) < 20000)

#### rarefy data ####
set.seed(24) #you must set a numerical seed like this for reproducibility
project_data.rarefied <- rarefy_even_depth(project_data, sample.size = min(sample_sums(project_data)))

#### Creat Colour Palettes ####
# 1. identify the number of colors you need from the factor you want to plot by
numcol <- length(unique(sample_data(project_data)$factor1)) #EXAMPLE ONLY, adjust per object being plotted
# 2. use a number seed to determine how qualpar samples your colors from its palette
set.seed(13)
# 3. use qualpalr colour palettes for easily distinguishing taxa
newpal <- qualpal(n = numcol, colorspace = "pretty")
# 4. If you want to color only a few things in the plot, try using a more colourblind-friendly palette:
cbPalette <- c("#E69F00", "#56B4E9", "#000000", "#009E73", "#CC79A7", "#0072B2", "#D55E00", "#FFFF00", "#999999", "#FF00FF", "#F0E442", "#FFFFFF", "#00FFFF")


#### basic alpha div plot ####
#chao1
pdf("AlphaDiversity.chao1.factor.experiment_name.pdf", #name of file to print. can also include relative or absolute path before filename.
    width = 16, height = 9)# define plot width and height. completely up to user.
p <- plot_richness(project_data.rarefied, x="factor", color = "factor", measures=c("Chao1"))
p + geom_boxplot(outlier.colour = "red", outlier.shape = 13) + 
  facet_grid(~ factor2) + #use this to divide data into separate plots based on a factor/variable
  theme(strip.background = element_rect(fill="white"), strip.placement = "bottom") +
  theme(strip.text = element_text(colour = 'black')) +
  theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank()) +
  scale_fill_manual(values=cbPalette) + scale_colour_manual(values=cbPalette) + 
  labs(title="Alpha Diversity, Factor N, Chao1", x="Factor1 ~ Factor2", y="Richness/Alpha Diversity")
dev.off()
#### calculate alpha diversity and add it as a column in the metadata ####
project_data.chao1 = estimate_richness(project_data.rarefied, split = TRUE, measures = c("Chao1")) #estimate richness
sample_data(project_data.rarefied)$chao1 <- project_data.chao1$Chao1 #add to metadata (the rows are in the same order already)
sample_data(project_data.rarefied)$chao1 <- as.numeric(sample_data(project_data.rarefied)$chao1)

#### beta diversity (NMDS, PCoA, etc.) ####
#do ordinations
set.seed(24)
NMDS.bray <- ordinate(
  physeq = project_data, 
  method = "NMDS", 
  distance = "bray"
) # you can choose different methods and distance metrics, see the ordinate help page for details. this function works with "phyloseq" class objects.

#### making beta div plots ####
#we get more plotting control if we don't use the phyloseq plotting functions for ordination plots, and instead add the results of the ordination to our existing metadata
NMDS <- as.data.frame(sample_data(project_data))
bray <- as.data.frame(NMDS.bray$points)
row.names(bray) == row.names(NMDS) #sanity check #tests as true
NMDS$NMDS.bray1 <- bray$MDS1
NMDS$NMDS.bray2 <- bray$MDS2
#OPTIONAL: sort data for better looking easier to read plots
NMDS.sort <- NMDS[order(NMDS$factor1, NMDS$factor2),]

#plain NMDS plot colored by "factor1" and shaped by "factor2"
pdf("NMDS.expt_name.factor1_color.factor2_shape.pdf"
    , width = 16 # Default is 7
    , height = 9 # Change to 10; make it taller
)
p <- ggplot(NMDS.sort, aes(x=NMDS.bray1, y=NMDS.bray2, shape = factor2, color = factor1))
p + geom_point(size=4) + scale_shape_manual(values=1:nlevels(NMDS.sort$factor2)) +
  labs(title="NMDS Factor1 & Factor2") + 
  scale_fill_manual(values=cbPalette) + scale_colour_manual(values=cbPalette) +
  theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(), axis.line = element_line(colour = "black"))
dev.off()

#facet wrapped NMDS plot
pdf("NMDS.expt_name.factor1~factor2.pdf"
    , width = 16 # Default is 7
    , height = 8 # Change to 10; make it taller
)
p <- ggplot(NMDS.sort, aes(x=NMDS.bray1, y=NMDS.bray2, color = factor3, shape = factor2))
p + facet_wrap(~factor1) + geom_point(size=4) +
  theme(strip.background = element_rect(fill="white"), panel.grid.major = element_blank(), panel.grid.minor = element_blank(), panel.spacing = unit(0.2, "lines")) +
  labs(title="NMDS Factor2 & Factor3 ~ Factor1") + 
  scale_fill_manual(values=cbPalette) + scale_colour_manual(values=cbPalette) +
  theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(), axis.line = element_line(colour = "black"))
dev.off()