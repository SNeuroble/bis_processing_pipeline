#!/bin/bash

##########################################################
#
# Authors: Stephanie Noble & Javid Dadashkarimi
# Based on Corey Horien and Stephanie Noble's scripts
# 
# Usage:
#i
# 1. Requires software: BIS (legacy), AFNI, SPM, FSL, Matlab
# 2. Data must be in BIDS format (e.g., subID/session1/func/task1\_run1.nii.gz, subID/session1/anat, etc)
# 3. Specify study parameters (and other settings if desired) in config file (see configs/cfg.sh)
# 4. Run:    bis_preprocessing_pipeline.sh <config_file>
#       > Example:     bis_preprocessing_pipeline.sh configs/cfg.sh
#
# Overview:
#
# Step 0. Setup
# Step 1. Skull stripping (optiBET)
# Step 2. Nonlinear registration of subject anatomicals to common space 
# Step 3. Slice time correction (SPM)
# Step 4. Motion correction (SPM)
# Step 5. Linear registration of mean functionals to subject anatomicals
# Step 6. Final check of previous steps
# Step 7. Final Study Processing (GLM, Connectivity, etc) 
#
# Output: Processed data (e.g., statistical images, connectivity, etc) in results/ folder
#
##########################################################




# Step 0. Setup

source $1
mktemp $tmp_file tee -a $log_file

# Setup scan IDs (folders containing func/anat)
# Case 1. func/anat under subject folders
# > scan_IDs=subject names
ls -d "$data_path" > $scan_IDs

# Case 2. func/anat under subject/session folders (or other subdirectory)
# > scans_IDs=subject+subdir names
if [[ ! -d "$data_path/$(sed -n 1p $scan_IDs)/anat" ]]; then
    find "$data_path" -maxdepth 2 -mindepth 2 > $tmp_file
    rev <$tmp_file | cut -f1,2 -d'/' | rev > $scan_IDs
fi

# Find names of functional images, removing any slicetime/motion corrected images
ls "$data_path/$(sed -n 1p $scan_IDs)/func/*nii.gz" > $func_names
sed -i.bak '/'"${slicetime_img_prefix}"'/d' $func_names
sed -i.bak '/'"${motion_corr_img_prefix}"'/d' $func_names
sed -i.bak '/'"$(mean_func_basename .nii.gz)"'/d' $func_names

ls "$data_path/$(sed -n 1p $scan_IDs)/anat/*nii.gz" > $anat_name
sed -i.bak '/'"${stripped_anat_suffix}"'/d' $anat_name

n_scans=$(wc $scan_IDs)
n_funcs=$(wc $func_names)




#############################################################
# Step 1. Skull Stripping

printf "Step 1. Skull Stripping \n Stripping scan " tee -a $log_file
for ((scan=1; scans<$n_scans; scan++)); do

    scan_ID=$(sed "${scan}q;d" $scan_IDs)
    printf "$scan_ID " tee -a $log_file
    anat_dir=$data_path/$scan_ID/anat
    anat_img=$anat_dir/${anat_basename}${ext}

    if [[ ! $(ls -A $anat_dir/*$optibet_suffix) ]]; then
        "$optibet -i $anat_img"
    else; printf "(skipped - already completed) " tee -a $log_file 
    fi

done




#############################################################
# Step 2. Nonlinear Registration

printf "\n\nStep 2. Nonlinear Registration (anat -> reference) \nRegistering scan " tee -a $log_file
for ((scan=1; scans<$n_scans; scan++)); do 

    scan_ID=$(sed "${scan}q;d" $scan_names)
    printf "$scan_ID " tee -a $log_file
    anat_dir=$data_path/$scan_ID/anat
    stripped_anat=$anat_dir/${anat_basename}${optibet_suffix}${ext}
    
    if [[ ! $(ls -A $anat_dir/*$nonlinear_trans_suffix) ]]; then

        nonlinear_setup_file=$out_path/nonlinear_setup_$dataset_name
        cp $templates_path/nonlinear_setup_template $nonlinear_setup_file
        sed -i "s#Xreference_img#${reference_img}#g" $nonlinear_setup_file
        sed -i "s#Xanat_img#${stripped_anat}#g" $nonlinear_setup_file
        sed -i "s#Xnonlinear_trans_suffix#${nonlinear_trans_suffix}#g" $linear_setup_file
        
        bis_makebatch.tcl -odir $anat_dir -setup $nonlinear_setup_file -makefile $out_path/nonlinear.make
        make -f $out_path/nonlinear.make -j $n_jobs
    
    else; printf "(skipped - already completed) " tee -a $log_file 
    fi

done




#############################################################
# Step 3. Slice Time Correction

if [[$do_slicetime]]; then

    printf "\n\nStep 3. Slice Time Correction \n " tee -a $log_file
    for ((scan=1; scans<$n_scans; scan++)); do

        scan_ID=$(sed "${scan}q;d" $scan_names)
        func_dir=$data_path/$scan_ID/func

        if [[ ! $(ls -A $func_dir/$slicetime_img_prefix*) ]]; then

            slicetime_script=$out_path/slicetime_correction_$dataset_name.csh
            cp $templates_path/slicetime_correction_template.csh $slicetime_script
            sed -i "s#Xsoftware_path#${spm_path}#g" $slicetime_script
            sed -i "s#Xfunc_dir#${func_dir}#g" $slicetime_script
            sed -i "s#Xnslices#${nslices}#g" $slicetime_script
            sed -i "s#Xtr#${tr}#g" $slicetime_script
            sed -i "s#Xfilter_expression#${filter_expr}#g" $slicetime_script
            sed -i "s#Xslice_acquisition_direction#${slice_acquisition_direction}#g" $slicetime_script

            # multi-line edits for study list
            for ((this_func=1; this_func<=$n_funcs; this_func++)); do
                func_name=$(sed "${this_func}q;d" $func_names)
                if [[ $this_func==1 ]]; then; separator=""
                else; separator=", "
                fi
                sed -i "s#Xstudy_list#${separator}'$func_name'Xstudy_list#g" $slicetime_script
            done

            $slicetime_script

        else; printf "(skipped - already completed) " tee -a $log_file
        fi

    done
    filter_expr=$slicetime_img_prefix

else; printf "\n\nSkipping Step 3. Slice Time Correction (user specification)\n " tee -a $log_file
fi



#############################################################
# Step 4. Motion Correction & Mean Functional

printf "\n\nStep 4. Motion Correction & Mean Functional \nCorrecting scan " tee -a $log_file
for ((scan=1; scans<$n_scans; scan++)); do

    scan_ID=$(sed "${scan}q;d" $scan_names)
    printf "$scan_ID " tee -a $log_file
    func_dir=$data_path/$scan_ID/func
    mean_func=$func_dir/$mean_func_basename

    if [[ ! $(ls -A $func_dir/$motion_img_prefix*) ]]; then

        motion_script=$out_path/motion_correction_template_$dataset_name.csh
        cp $templates_path/motion_correction_template.csh $motion_script
        sed -i "s#Xsoftware_path#${spm_path}#g" $motion_script
        sed -i "s#Xfunc_dir#${func_dir}#g" $motion_script
        sed -i "s#Xfilter_expression#${filter_expr}#g" $motion_script
        sed -i "s#Xmotion_dir#${motion_params_dir_suffix}#g" $motion_script
        sed -i "s#Xuse_old_moco#${use_old_moco}#g" $motion_script

        # multi-line edits for study list
        for ((this_func=1; this_func<=$n_funcs; this_func++)); do
            func_name=$(sed "${this_func}q;d" $func_names)
            if [[ $this_func==1 ]]; then; separator=""
            else; separator=", "
            fi
            sed -i "s#Xstudy_list#${separator}'$func_name'Xstudy_list#g" $motion_script
        done

        sed -i "s#Xmean_func_file#${mean_func}#g" $motion_script

        $motion_script 

    else; printf "(skipped - already completed) " tee -a $log_file
    fi

done




#############################################################
# Step 5. Linear Registration

printf "\n\nStep 5. Linear Registration (mean func -> anat) \nRegistering scan " tee -a $log_file

for ((scan=1; scans<$n_scans; scan++)); do

    scan_ID=$(sed "${scan}q;d" $scan_names)
    printf "$scan_ID " tee -a $log_file
    func_dir=$data_path/$scan_ID/func
    anat_dir=$data_path/$scan_ID/anat
    stripped_anat=$anat_dir/${anat_basename}${optibet_suffix}${ext}

    if [[ ! $(ls -A $func_dir/*$linear_trans_suffix) ]]; then

        linear_setup_file=$out_path/linear_setup_$dataset_name
        cp $templates_path/linear_setup_template $linear_setup_file
        sed -i "s#Xstripped_img#${stripped_anat}#g" $linear_setup_file
        sed -i "s#Xmean_func#${mean_func}#g" $linear_setup_file
        sed -i "s#Xlinear_trans_suffix#${linear_trans_suffix}#g" $linear_setup_file
       
        bis_makebatch.tcl -odir $func_dir -setup $linear_registeration_setup_file -makefile $out_path/linearregisteration.make
        make -f $out_path/linearregisteration.make -j $n_jobs

    else; printf "(skipped - already completed) " tee -a $log_file
    fi

done




#############################################################
# Step 6. Final Check Of Previous Steps

transform_img_for_check=0
printf "\n\nStep 6. Final Check Of Previous Steps " tee -a $log_file
read -rep $'\n\nProceed to final study processing (enter \"yes\"/\"no\")? \nIMPORTANT: Visual inspection of the previous steps is strongly encouraged before proceeding. If you have not completed visual inspection, enter \"no\" and you will have the option to create files for visual inspection.' response_step7
if [[ "$response_step7" =~ "no" ]]; then
    read -rep $'Create transformed mean functionals for visual inspection? \nThis transforms each mean functional image to common space, enabling inspection of whether all above steps succeeded.' response_transform
    if [[ "$response_transform" =~ "yes" ]]; then; transform_img_for_check=1
    elif [[ "$response_transform" =~ "no" ]]; then; printf "\nOkay, stopping without transforming mean functional." tee -a $log_file; exit 0
    else; printf "\nUser did not respond yes or no. Stopping without transforming mean functional." tee -a $log_file; exit 0
    fi
elif [[ "$response_step7" =~ "yes" ]]; then; printf "\nOkay, continuing to final study processing." tee -a $log_file
else; printf "\nUser did not respond yes or no. Stopping." tee -a $log_file; exit 0
fi


if [[ $transform_img_for_check ]]; then
    printf "\n\nTransforming mean functionals.\nTransforming scan " tee -a $log_file
    for ((scan=1; scans<$n_scans; scan++)); do
        scan_ID=$(sed "${scan}q;d" $scan_names)
        printf "$scan_ID " tee -a $log_file
        anat_dir=$data_path/$scan_ID/anat
        func_dir=$data_path/$scan_ID/func
        mean_func=$func_dir/$mean_func_basename
        nonlinear_transform=$(ls -A $anat_dir/*$nonlinear_trans_suffix)
        linear_transform=$(ls -A $func_dir/*$linear_trans_suffix)
        combined_transform=$func_dir/$combined_transform_basename
        transformed_mean_func=$func_dir/$($mean_func_basename .nii.gz)$transformed_mean_func_suffix
        if [[ ! -f $transformed_mean_func ]]; then
            bis_combinetransformations.tcl -inp $mean_func -inp2 $nonlinear_transform -inp3 $linear_transform -out $combined_transform
            bis_resliceimage.tcl -inp $mean_func -inp2 $combined_transform -out $transformed_mean_func 
        else; printf "(skipped - already completed) " tee -a $log_file
        fi
    done
    exit 0
fi



#############################################################
# Step 7. Final Study Processing

printf "\n\nStep 7. Final Study Processing (GLM, Connectivity, etc) \nProcessing subject " tee -a $log_file

source $scripts_path/modify_study_setup_files.sh

for ((scan=1; scans<$n_scans; scan++)); do
   
    scan_ID=$(sed "${scan}q;d" $scan_names)
    printf "$scan_ID " tee -a $log_file
    if [[ ! -f "$out_path/*${processing_type}.nii.gz" ]]; then
        bis_fmrisetup.tcl $study_setup_file ${processing_type}
    else; printf "(skipped - already completed) " tee -a $log_file
    fi

done

printf "All processing complete.\n" tee -a $log_file




