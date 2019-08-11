#!/bin/bash

# Make study-specific edits followed by scan-specific edits to setup file 
# IMPORTANT: overwrites existing setup files without checking

# Study-specific edits
study_setup_file=$out_path/study_setup_${dataset}.xmlg
cp $scripts_path/study_setup_template.xmlg $study_setup_file
sed -i "s#Xdataset_nameX#${dataset}#g" $study_setup_file
sed -i "s#Xoutput_dirX#${out_path}#g" $study_setup_file
sed -i "s#Xreference_imgX#${reference_img}#g" $study_setup_file
sed -i "s#Xwm_csf_imgX#${wm_csf_img}#g" $study_setup_file
sed -i "s#XtrX#${tr}#g" $study_setup_file # make scan-specfic?
sed -i "s#Xn_slicesX#${n_slices}#g" $study_setup_file # make scan-specific?
sed -i "s#Xn_framesX#${n_frames}#g" $study_setup_file # make scan-specific?
sed -i "s#XparcellationX#${parcellation}#g" $study_setup_file
sed -i "s#Xidentity_matrixX#${identity_mat}#g" $study_setup_file
sed -i "s#XgsrX#${do_GSR}#g" $study_setup_file
sed -i "s#Xtemporal_sigmaX#${temporal_sigma}#g" $study_setup_file


# Scan-specific edits
for ((scan=1; scans<$n_scans; scan++)); do

    scan_ID=$(sed "${scan}q;d" $scan_names)
    scan_ID_noslash=$(sed %s/\.*\/_/g $scan_ID) # all one string for naming purposes if multiple sessions TODO: fix this
    anat_dir=$data_path/$scan_ID/anat
    func_dir=$data_path/$scan_ID/func
    anat_img=$anat_dir/${anat_basename}${ext}
    nonlinear_transform=$(ls $anat_dir/*$nonlinear_trans_suffix)
    nonlinear_transform_inverse=$(dirname nonlinear_transform)/Inverse_$(basename $nonlinear_transform)
    linear_transform=$(ls $anat_dir/*$linear_trans_suffix)
    study_scan_setup_file=$out_path/study_setup_${dataset}_${scanID_noslash}.xmlg

    cp $study_setup_file $study_scan_setup_file
    sed -i "s#XsubjectIDX#${scan_ID_noslash}#g" $study_scan_setup_file
    sed -i "s#XanatX#${anat_img}#g" $study_scan_setup_file
    sed -i "s#Xnonlinear_transformX#${nonlinear_transform}#g" $study_scan_setup_file
    sed -i "s#Xlinear_transformX#${linear_transform}#g" $study_scan_setup_file
    sed -i "s#Xlinear_transform_inverseX#${linear_transform_inverse}#g" $study_scan_setup_file
    sed -i "s#XfuncX#${func_img}#g" $study_scan_setup_file
    sed -i "s#XmotX#${motion_data}#g" $study_scan_setup_file
    sed -i "s#Xmean_func_file#${mean_func}#g" $motion_script

    for ((this_func=1; this_func<=$n_funcs; this_func++)); do
        func_name=$(sed "${this_func}q;d" $func_names)
        motion_corr_func=$(ls $func_path/${motion_corr_img_prefix}*${func_name}*nii.gz)
        motion_params=ls $(dirname $motion_corr_func)/$(basename $motion_corr_func .nii.gz)${motion_params_suffix}.nii.gz

        if [[ $this_func==1 ]]; then; separator=""
        else; separator="\n"
        fi
        
        sed -i "s#XfuncX#${separator}'$motion_corr_func'Xstudy_list#g" $study_scan_setup_file
        sed -i "s#Xfunc_motionX#${separator}'$motion_params'Xstudy_list#g" $study_scan_setup_file
    done

done

