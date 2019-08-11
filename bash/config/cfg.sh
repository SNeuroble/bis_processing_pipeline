# Settings for fMRI processing pipeline

######## USER-DEFINED #########
# Study-specific data_paths & substrings

data_path='/Volumes/GoogleDrive/My Drive/Steph - Lab/Misc/Software/scripts/bash/bis_processing_pipeline/bash/testing'
dataset_name="tom"
processing_type="matrix"




###### TECHNICAL SETTINGS ########
# No need to touch these if you're okay with the defaults

# Scripts paths - TODO: these should be local to this script
scripts_path="/Volumes/GoogleDrive/My Drive/Steph - Lab/Misc/Software/scripts/bash/bis_processing_pipeline/bash" # TODO: probably can just get path of this script
dustin_scripts_path="/data_dustin/dataset/scripts"

# Software paths
matlab="/usr/bin/matlab"
spm_path="/data1/software/spm8"
optibet="/data1/software/optiBET.sh"
templates_path="$scripts_path/templates"

# Input filenames and components - TODO: check this
out_path="${data_path}_results"
stripped_anat_suffix="optiBET_brain.nii.gz"
nonlinear_trans_suffix="3rdpass.grd"
linear_trans_suffix="linear.matr"
slicetime_img_prefix="A_"
motion_corr_img_prefix="R_"
mean_func_basename="mean_func.nii.gz"
combined_tranform_basename="mean_func_to_reference.grd"
transformed_mean_func_suffix="__reference.nii.gz"
motion_params_dir_suffix="_realign"
motion_params_suffix="_bold_hiorder.mat"
ext=".nii.gz"
filter_expr=${ext}
reference_img="/data1/software/bioimagesuite35/images/MNI_T1_1mm_stripped.nii.gz"
wm_csf_img="/data_dustin/dataset/example/MNI_1mm_WM_CSF_erode.nii.gz"
parcellation="$dustin_scripts_path/shen_1mm_268_parcellation.nii"
identity_mat="$dustin_scripts_path/i.matr"

# Output files
scan_IDs="$out_path/scan_IDs"
func_names="$out_path/func_names"
log_file="$out_path/log"
tmp_file="/tmp/bis_processing_script.XXXXXX"

# Software params - TODO: should read params (after slice_acquisition) from data descrip
n_jobs=3 # for running registrations
do_slicetime=1
do_GSR=1 # for study processing
temporal_sigma='1.0' # for study processing
slice_acquisition_direction="ascending"
tr=2
n_slices=32
n_frames=600
skip_frames_on=1
use_old_moco=0




