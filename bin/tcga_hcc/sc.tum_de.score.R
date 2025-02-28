
setwd("../../")

library(Seurat)
library(grid)
library(gtable)
library(ggplot2)
library(ggrepel)
library(scales)
library(gridExtra)
library(reshape2)

#=========================================
# Functions
#=========================================

create_dir <- function(p){
    dir.create(p, showWarnings=FALSE, recursive=TRUE)
}

#' @param datf data frame to get median points from
#' @param x character vector of column names to calculate median for
#' @param groupby the column name to group the rows of the data frame by
get_med_points <- function(datf, x, groupby){
    groups <- sort(unique(datf[,groupby]))
    gs.l <- lapply(groups, function(gr){
                 k <- datf[,groupby] == gr
                 datf.s <- datf[k, x, drop=FALSE]
                 r <- apply(datf.s, 2, median)
                 return(r) })
    names(gs.l) <- groups
    gs <- as.data.frame(do.call(rbind, gs.l))
    colnames(gs) <- x
    rownames(gs) <- groups
    return(gs)
}

#=========================================
#=========================================

# Gene data
gene_info <- read.table("data/ref/gencode26/gencode.v26.annotation.txt", 
                        header = TRUE, 
                        row.names = 1, 
                        stringsAsFactors = FALSE, 
                        sep = "\t")
gene_info[,"Name"] <- make.unique(gene_info[,"Name"])
symb2ens <- rownames(gene_info)
names(symb2ens) <- gene_info[,"Name"]

ens_id <- rownames(gene_info)
names(ens_id) <- gsub("\\..*", "", ens_id)

# Set directories
dir_exp <- "exp/tcga_hcc/sharma_aiz.tum_score/";
dir.create(dir_exp, showWarnings=FALSE, recursive=TRUE)

fn <- "data/processed/sharma_aiz/liver.int_rand.rds"
integrated <- readRDS(fn)

fn <- "exp/tcga_hcc/de/de.table.tsv.gz"
de <- read.table(fn, header=TRUE, sep='\t', row.names=1)
de[,"ens"] <- ens_id[de[,"gene_id"]]

reds <- read.csv("data/ref/colors/red_colrs.csv", header=FALSE)
reds <- reds[,1]

#=========================================
# score tum-enr genes
#=========================================

DefaultAssay(integrated) <- "RNA"
de.k <- de[de[,"ens"] %in% rownames(integrated),]

k <- de.k[,"logFC"] > 1 & de.k[,"p_adj"]  < 0.05
tum_genes <- de.k[k,"ens"]
# tum_genes <- de.k[k,"ens"][1:1000]
# 1,065 significant up-regulated genes
message(length(tum_genes), " DE genes found")

integrated.m <- AddModuleScore(integrated, 
                               features=list("TumEnr" = tum_genes), 
                               name = "TumEnr")

md <- integrated.m@meta.data

out_fn <- paste0(dir_exp, "sharma_aiz.tum_enr_scores.txt")
write.table(md[,"TumEnr1",drop=FALSE], out_fn, row.names=TRUE, 
            col.names=NA, quote=FALSE, sep='\t')

#=========================================
# wilcoxon test per cell-type
#=========================================

cl_ids <- c("cell_type_main", "cell_type_fine")
for (cl_id in cl_ids){
    cts <- sort(unique(md[,cl_id]))
    tum_diffs <- list()
    for (ct in cts){
        k <- md[,cl_id] == ct
        x1 <- md[k,"TumEnr1"]
        x2 <- md[!k,"TumEnr1"]
        wret <- wilcox.test(x = x1, y = x2)
        tret <- t.test(x = x1, y = x2)
        rdatf <- data.frame("mean_ct" = mean(x1), 
                            "mean_nonct" = mean(x2), 
                            "t_statistic" = tret$statistic, 
                            "t_p" = tret$p.value, 
                            "w_statistic" = wret$statistic, 
                            "w_p" = wret$p.value)
        tum_diffs[[ct]] <- rdatf
    }
    tum_diffs <- do.call(rbind, tum_diffs)
    tum_diffs[,"t_p_adj"] <- p.adjust(tum_diffs[,"t_p"], method="fdr")
    tum_diffs[,"w_p_adj"] <- p.adjust(tum_diffs[,"w_p"], method="fdr")
    out_fn <- paste0(dir_exp, cl_id, ".diff_stat.txt")
    write.table(tum_diffs, out_fn, row.names=TRUE, col.names=NA, 
                quote=FALSE, sep='\t')
}

#=========================================
# common plotting theme
#=========================================

theme_trnsp <- theme(plot.background = element_rect(fill="transparent", color=NA),
                     panel.background = element_rect(fill="transparent", color=NA),
                     gend.background = element_rect(fill="transparent", color=NA))

theme_txt <- theme(text = element_text(size = 8),
                   plot.title = element_text(hjust = 0.5))

theme_leg <- theme(legend.key.height = unit(1, "strheight", "0"),
                   legend.key.width = unit(1, "strwidth", "0"))

theme_axs <- theme(axis.text=element_blank(),
                   axis.ticks=element_blank())

theme_s <- theme_classic() + 
    theme_txt + theme_leg + theme_axs

#=========================================
# merge UMAP and meta data
#=========================================

udf <- integrated.m@reductions$umap@cell.embeddings
colnames(udf) <- c("UMAP1", "UMAP2")
udf <- cbind(udf, integrated.m@meta.data[rownames(udf),])

set.seed(1, kind = 'Mersenne-Twister')
udf <- udf[sample(1:nrow(udf)),]

#=========================================
# Plot Tum Enr Score
#=========================================

feat <- "TumEnr1"; lt <- "Tumor Enrichment"
o <- order(udf[,"TumEnr1"], decreasing=FALSE)
p <- ggplot(udf[o,], aes(x=UMAP1, y=UMAP2, color=TumEnr1)) + 
    geom_point(size = 0.01, shape = 16) + 
    theme_s + ggtitle("NASH-HCC + Aizarani + Sharma") + 
    scale_color_gradientn(colours = reds, name =  lt)

outfn <- file.path(dir_exp, "UMAP.TumEnr.pdf")
ggsave(outfn, width = 3.5, height = 3, dpi=300)
pname <- gsub("pdf$", "png", outfn)
ggsave(pname, width = 3.5, height = 3, dpi=300)

# box plot of enr scores (main)
p <- ggplot(udf, aes(x = cell_type_main, y = TumEnr1)) + 
geom_boxplot(outlier.shape=16, outlier.size=0.1, outlier.alpha=0.1) + 
theme_classic() + 
ylab("Tumor Enrichment") + 
xlab(NULL) + 
ggtitle(NULL) + 
theme(text = element_text(size = 8),
      axis.text.x = element_text(angle=90, hjust=1, vjust=0.5, size=8), 
      plot.title = element_text(hjust = 0.5))

ggsave(paste0(dir_exp, "box.main.TumEnr.pdf"), width = 3, 
       height = 3, dpi = 300)

# box plot of enr scores (fine)
p <- ggplot(udf, aes(x = cell_type_fine, y = TumEnr1)) + 
geom_boxplot(outlier.shape=16, outlier.size=0.1, outlier.alpha=0.1) + 
theme_classic() + 
ylab("Tumor Enrichment") + 
xlab(NULL) + 
ggtitle(NULL) + 
theme(text = element_text(size = 8),
      axis.text.x = element_text(angle=90, hjust=1, vjust=0.5, size=8), 
      plot.title = element_text(hjust = 0.5))

ggsave(paste0(dir_exp, "box.fine.TumEnr.pdf"), width = 5, 
       height = 3, dpi = 300)

