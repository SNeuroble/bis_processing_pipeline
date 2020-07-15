# Settings for fMRI processing pipeline

######## USER-DEFINED #########
# Study-specific data_paths & substrings

data_path="/data15/mri_group/smn33_data/test_pipeline/sample"
processing_type="matrix"
subID_filter_expression="constable" # leave empty to use bids default subject naming; otherwise provide string that will match subject IDs, e.g., "constable" for "pa0668_constable"

# Acquisition info - get from series info (TODO: should be able to automatically read from SeriesInfo or 3dinfo instead of manually set)
slice_acquisition_direction="ascending" # TODO: how to automate, where to find? options are ascending, descending, or descending_interleaved
tr=1 # get from Series Info "Repetition Time"
n_slices=75 # get from Series Info - NumberOfImagesInMosaix
n_frames=600 # used in the study_setup
skip_frames_on=1 # TODO - need this?
MPR_scan_suffix='_stack3d_S003' # get from Series Info - Scan




###### TECHNICAL SETTINGS ########
# No need to touch these if you're okay with the defaults

# Scripts paths - TODO: these should be local to this script
scripts_path="/mridata2/home2/smn33/scripts/analysis/processing_pipeline" #TODO: this is the only things to change when space is restored on the home dir
#reference_path="/data_dustin/dataset/scripts"
#reference_path="/data1/software/bioimagesuite35/images"
reference_path="/mridata2/home2/smn33/bioimagesuite30_src/bioimagesuite/images"


# Software paths
bis_setpaths="/data1/software/bioimagesuite35/setpaths.sh"
matlab="/usr/local/bin/matlab"
spm_path="/data1/software/spm8"
#optibet="/mridata2/home2/smn33/scripts/analysis/optiBET.sh"
optibet="/data1/software/optiBET.sh"
templates_path="$scripts_path/templates"

# BIDS defaults - don't touch
sub_bids_prefix="sub-"
ses_bids_prefix="ses-"
func_bids_prefix='func'
anat_bids_prefix='anat'

# Reference images
reference_img="$reference_path/MNI_T1_1mm_stripped.nii.gz"
wm_csf_img="$reference_path/MNI_1mm_GM_WM_CSF_erode.nii.gz"
#wm_csf_img="$reference_path/example/MNI_1mm_WM_CSF_erode.nii.gz"
parcellation="$reference_path/shen_atlas/shen_1mm_268_parcellation.nii"
identity_mat="$reference_path/i.matr"

# Miscellaneous file parts
out_path="${data_path}_results"
dataset_name="$(basename ${data_path})"
stripped_suffix="_optiBET_brain.nii.gz" # don't touch - defined by the mrrc slicetime script
nonlinear_trans_suffix="_map"
nonlinear_trans_ext=".grd" # don't touch - defined by the nonlinear reg script
nonlinear_final_pass="3rdpass" # don't touch - defined by the nonlinear reg script
linear_trans_suffix="_map" 
linear_trans_ext=".matr" # don't touch - defined by the linear reg script
slicetime_prefix="A" # don't touch - defined by the mrrc slicetime script
motion_corr_prefix="R_" # don't touch - defined by the mrrc moco script
motion_params_topdir="motion_params" 
motion_params_suffix="_hiorder.mat" # don't touch - defined by the mrrc moco script
mean_func_prefix="mean" # don't touch - defined by the mean img script
#mean2ref_transform_basename="mean_func_to_reference.grd"
mean_func_in_ref_prefix="reference_spc__"

# Output files
sub_IDs="$out_path/sub_IDs"
func_names="$out_path/func_names"
anat_names="$out_path/anat_names"
log_file="$out_path/log"
tmp_file="/tmp/bis_processing_script.XXXXXX"

# Computing and analysis params
n_jobs=3 # for running registrations
do_slicetime=true # not always necessary for estimating connectivity
do_GSR=true # for study processing # TODO: pass this param
temporal_sigma='1.0' # for study processing
use_old_moco=0 # TODO: pass this param
moco_to_middle_run=0 # default=0; pretty much don't touch this unless you need to



