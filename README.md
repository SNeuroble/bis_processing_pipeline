# BIS Processing Pipeline
fMRI Preprocessing Pipeline for BIS

## Getting Started

### Preprequisites
1. Required software: BIS (legacy), FSL, AFNI, SPM, Matlab

2. Data must be in BIDS format (e.g., subID/session1/func/task1\_run1.nii.gz, subID/session1/anat, etc.)


### User-defined Parameters

1. User-defined parameters must be specified in a config file (see config/cfg.sh). At minimum, users must specify information about study data.

### Overview

> Step 1. Skull stripping (optiBET)

> Step 2. Nonlinear registration of subject anatomicals to common space (BIS)

> Step 3. Slice time correction (SPM)

> Step 4. Motion correction (SPM)

> Step 5. Linear registration of mean functionals to subject anatomicals (BIS)

> Step 6. Final check of previous steps

> Step 7. Final Study Processing (GLM, connectivity, etc; BIS) 

### Usage
`bis_preprocessing_pipeline.sh <config_file>`

Example: `bis_preprocessing_pipeline.sh configs/cfg.sh`

