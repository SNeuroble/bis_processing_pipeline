#!/bin/bash
#set -x
##########################################################
#
# Authors: Stephanie Noble & Javid Dadashkarimi
# Based on Stephanie Noble & Corey Horien's protocols
# 
# Usage:
#
# 1. Required software: BIS (legacy), AFNI, SPM, FSL, Matlab
# 2. Data must be converted into nifti and in BIDS format (e.g., subID/sessionID/func/task1_run1.nii.gz)
# 3. Specify study parameters (and other settings if desired) in config file (see configs/cfg.sh)
# 4. Run:    bis_preprocessing_pipeline.sh <config_file>
#       > Example:     bis_preprocessing_pipeline.sh configs/cfg.sh
#
# Overview:
#
# * STEP 0. Setup
# * STEP 1. Skull stripping (optiBET)
# * STEP 2. Nonlinear registration of subject anatomicals to common space 
# * STEP 3. Slice time correction (SPM)
# * STEP 4. Motion correction (SPM)
# * STEP 5. Linear registration of mean functionals to subject anatomicals
# * STEP 6. Final check of previous steps
# * STEP 7. Final Study Processing (GLM, connectivity, etc) 
#
# Output: Processed data (e.g., statistical images, connectivity, etc) in results/ folder
#
##########################################################




# *** STEP 0. Setup

source $1
source $bis_setpaths
mkdir -p $out_path
#mktemp $tmp_file | tee -a $log_file
touch $tmp_file

# Get subject IDs (folders containing func/anat)
# TODO: save subIDs and maybe func/anat to variable instead of reading/writing to doc each time
if [ -z "$subID_filter_expression" ]; then subID_filter_expression=$sub_bids_prefix; fi
ls -d ${data_path}/*/ > $tmp_file
grep $subID_filter_expression $tmp_file > $sub_IDs
sed -e "s#$data_path##g" -i "${sub_IDs}"
sed -e "s#/##g" -i "${sub_IDs}"
printf "Subject IDs here: $sub_IDs\n"

# Check for multiple sessions
#   - Single session naming: subID/anat, subID/func
#   - Multi-session naming: subID/sesID/anat, subID/sesID/func
# TODO: other file organizations to consider?
first_subID=$(head -1 $sub_IDs)
path__first_sub=${data_path}/${first_subID}
first_sess__first_sub="$path__first_sub/${ses_bids_prefix}1"

if [ -d "$first_sess__first_sub" ]; then
    do_session=true
    sess_str="$ses_bids_prefix*/"
else
    do_session=false
    sess_str=""
fi

# Record unprocessed functional filenames
# remove any slicetime, motion corrected, or mean images
# also erase .gz from files (will check for them .gz in the slicetime script and gunzip)
#ls $data_path/$(sed -n 1p $sub_IDs)/$func_bids_prefix/*nii* > $tmp_file
ls $data_path/*/${sess_str}${func_bids_prefix}/*nii* > $tmp_file
sed -i "s/.gz//g" $tmp_file
sed -i "\#/${slicetime_prefix}#d" $tmp_file
sed -i "\#/${motion_corr_prefix}#d" $tmp_file
sed -i "/${mean_func_prefix}/d" $tmp_file
sed -i "/ignore/d" $tmp_file # TODO: TEMPORARY, remove
sort -u $tmp_file > $func_names
#TODO: have we checked for everything?

# Record unprocessed anatomical filenames
# remove all optibet derivatives (optiBET, RAS, step)
# TODO: assuming here and in STEP 1 that files end in nii.gz.... safe?
#ls $data_path/$(sed -n 1p $sub_IDs)/$anat_bids_prefix/*nii.gz > $tmp_file
#sed -i.bak '/'"${anat_bids_prefixipped__sub_suffix}"'/d' $anat_names
ls $data_path/*/${sess_str}${anat_bids_prefix}/*${MPR_scan_suffix}*nii.gz > $tmp_file
sed -i "/optiBET/d" $tmp_file
sed -i "/RAS/d" $tmp_file
sed -i "/step/d" $tmp_file
cp $tmp_file $anat_names

n_subs=$(wc -l < $sub_IDs)

printf "Functional files here: ${func_names}\
    \nAnatomical files here: ${anat_names}\n"

# Count max no sessions
# TODO: how likely is it to only have anat file at first session but then functionals at multiple sessions?
if [ "$do_session" == true ]; then
    cp $anat_names $tmp_file
    sed -i "s#^.*/${ses_bids_prefix}\(.*\)/${anat_bids_prefix}.*#\1#g" $tmp_file
    n_sess=$(sort -u $tmp_file | tail -1)
else
    n_sess=1 
fi



#############################################################
# *** STEP 1. Skull Stripping

printf "Begin fMRI processing (7 steps).\n\n" tee -a $log_file

printf "*** STEP 1. Skull Stripping\n This step will take a while (~20 min/scan)... \n Now stripping scan:" tee -a $log_file

for ((sub=1; sub<=$n_subs; sub++)); do
for ((sess=1; sess<=$n_sess; sess++)); do

    {    
    sub_ID=$(sed "${sub}q;d" $sub_IDs)
    if [ "$do_session" == true ]; then
        sess_ID_grep_str="/$ses_bids_prefix$sess"
    fi
    printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file

    anat_img__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $anat_names) 
    if [ -f "$anat_img__sub" ]; then

        anat_stripped__sub=$(ls ${anat_img__sub%%.*}*${stripped_suffix} 2>/dev/null) # TODO:should we put wildcard at end too? Here and below?
        
        if [ ! -f "${anat_stripped__sub}" ]; then
            sh $optibet -i $anat_img__sub
        else printf "(SKIPPED - already exists) " tee -a $log_file 
        fi
    else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
    fi

    } || { # catch
    printf "Error during skull stripping, stopping here.\
        \nA common issue is that updated dependencies for optiBET only exist on a few computers. FSL dependency error will result \
        in \"Runtime error:- detected by Newmat: matrix is singular\". Last we checked it worked on shred but not wave or cuda5. \n"
    exit
    }

done
done

printf "\n"
# TODO: maybe stop for visual inspection



#############################################################
# *** STEP 2. Nonlinear Registration

printf "\n\n*** STEP 2. Nonlinear Registration (anat -> reference)\n This step will also take a while (~1-1.5 h/scan)...\n Registering scan:" tee -a $log_file

for ((sub=1; sub<=$n_subs; sub++)); do
for ((sess=1; sess<=$n_sess; sess++)); do

    {
    sub_ID=$(sed "${sub}q;d" $sub_IDs)
    if [ "$do_session" == true ]; then
        sess_ID_grep_str="/$ses_bids_prefix$sess"
    fi
    printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file

    anat_img__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $anat_names)
    if [ -f "$anat_img__sub" ]; then
       
        nonlinear_transform__sub=$(ls $(dirname $anat_img__sub)/[^I]*${nonlinear_final_pass}*${nonlinear_trans_ext} 2>/dev/null)
        # TODO: check that added 2>/dev/null to each ls command
        
        if [ ! -f "${nonlinear_transform__sub}" ]; then
            anat_stripped__sub=$(ls ${anat_img__sub%%.*}*${stripped_suffix} 2>/dev/null)
            nonlinear_setup_file=$out_path/nonlinear_setup_$dataset_name
            cp $templates_path/nonlinear_setup_template $nonlinear_setup_file
            sed -i "s#Xreference_img#${reference_img}#g" $nonlinear_setup_file
            sed -i "s#Xanat_img#${anat_stripped__sub}#g" $nonlinear_setup_file
            sed -i "s#Xnonlinear_trans_suffix#${nonlinear_trans_suffix}${nonlinear_trans_ext}#g" $nonlinear_setup_file
            bis_makebatch.tcl -odir $(dirname $anat_img__sub) -setup $nonlinear_setup_file -makefile $out_path/nonlinear.make
            make -f $out_path/nonlinear.make -j $n_jobs
        
        else printf "(SKIPPED - already exists) " tee -a $log_file 
        fi
    else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
    fi


    # TODO: add this via makebatch too: pxmat_inverttransform.tcl referenceimg outputtransform inputtransform

    } || { # catch
    printf "Error during nonlinear registration, stopping here.\
        \nA common issue is connecting without a display set. Check that you\'ve connected with ssh -X. \n"
    exit
    }

done
done

printf "\n"



#############################################################
# *** STEP 3. Slice Time Correction

if [ "$do_slicetime" = true ]; then

    printf "\n\n*** STEP 3. Slice Time Correction \n This step takes ~4-8 min/scan\n Correcting slicetime for scan:" tee -a $log_file
   
    for ((sub=1; sub<=$n_subs; sub++)); do
    for ((sess=1; sess<=$n_sess; sess++)); do

        {
        sub_ID=$(sed "${sub}q;d" $sub_IDs)
        if [ "$do_session" == true ]; then
            sess_ID_grep_str="/$ses_bids_prefix$sess"
        fi
        printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file

        # check whether any functionals exist for this sub/sess
        func_names__sub=($(grep "/$sub_ID$sess_ID_grep_str/" $func_names))
        if [ ! ${#func_names__sub[@]} -eq 0 ]; then

            last_func__sub=${func_names__sub[-1]}
            last_slicetime_corr_func__sub=$(ls $(dirname $last_func__sub)/${slicetime_prefix}*$(basename $last_func__sub)* 2>/dev/null) 
            
            # we'll just check for the last one, and if not completed we'll repeat all
            # TODO: find a better way
            # TODO: re above,  might be better to add the above steps into the below func loop to check all images and only add those that haven't been completed, in case a single functional did not complete for some reason
            if [ ! -f "$last_slicetime_corr_func__sub" ]; then
                
                slicetime_script=$out_path/slicetime_correction_$dataset_name.csh
                cp $templates_path/slicetime_correction_template.csh $slicetime_script
                sed -i "s#Xmatlab_path#${matlab}#g" $slicetime_script
                sed -i "s#Xlog_dir#${out_path}#g" $slicetime_script
                sed -i "s#Xsoftware_path#${spm_path}#g" $slicetime_script
                sed -i "s#Xfunc_dir#$(dirname $last_func__sub)#g" $slicetime_script
                sed -i "s#Xnslices#${n_slices}#g" $slicetime_script
                sed -i "s#Xtr#${tr}#g" $slicetime_script
                sed -i "s#Xslice_acquisition_direction#${slice_acquisition_direction}#g" $slicetime_script

                # multi-line edits for study list
                for ((func_no=0; func_no<${#func_names__sub[@]}; func_no++)); do
                    func_name=${func_names__sub[$func_no]}
                    if (( $func_no==0 )); then separator=""
                    else separator=", \n"
                    fi
                    sed -i "s#Xstudy_list#${separator}'$func_name'Xstudy_list#g" $slicetime_script
                done

                cp $slicetime_script $tmp_file
                sed -i "s#Xstudy_list##g" $tmp_file
                cp $tmp_file $slicetime_script
                if (( $sub==1 )) && (( $func_no==0 )); then
                    printf "\n Study-specific slicetime script: $slicetime_script\n"
                fi
                
                $slicetime_script 
                # TODO: here and below, should check the matlab output for errors and throw an error here

            else printf "(SKIPPED - already exists) " tee -a $log_file
            fi
        else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
        fi

        } || { # catch
        printf "Error during slice time correction, stopping here. \n"
        exit
        }
    
    done
    done
    printf "\n"
    

else
    printf "\n\n*** SKIPPING STEP 2. Slice Time Correction by popular demand (that is, user said to skip).\n " tee -a $log_file
    # set slicetime_prefix to be empty so can use for the rest of the script
    slicetime_prefix=""
fi



#############################################################
# *** STEP 4. Motion Correction & Mean Functional

printf "\n\n*** STEP 4. Motion Correction & Mean Functional\n This step takes ~11 min/scan\n Correcting motion for scan:" tee -a $log_file

for ((sub=1; sub<=$n_subs; sub++)); do
for ((sess=1; sess<=$n_sess; sess++)); do

    {
    sub_ID=$(sed "${sub}q;d" $sub_IDs)
    if [ "$do_session" == true ]; then
        sess_ID_grep_str="/$ses_bids_prefix$sess"
    fi
    printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file

    # check whether any functionals exist for this sub/sess
    # TODO: choose consistent naming: motion_correction, motion_corr, or moco
    func_names__sub=($(grep "/$sub_ID$sess_ID_grep_str/" $func_names))
    if [ ! ${#func_names__sub[@]} -eq 0 ]; then

        # check whether the last functional of this sub was completed - assuming this means all other funcs for this sub completed
        # note: this will not find files that have been re-gzipped since above we ensured naming ends in nii
        last_func__sub=${func_names__sub[-1]}
        last_motion_corr_func__sub="$(ls $(dirname $last_func__sub)/${motion_corr_prefix}*$(basename $last_func__sub)* 2>/dev/null)"

        if [ ! -f "${last_motion_corr_func__sub}" ]; then
            motion_params_dir__sub="$(dirname $last_func__sub)/${motion_params_topdir}/"
            if [ ! -d "${motion_params_dir__sub}" ]; then mkdir $motion_params_dir__sub; fi

            motion_script=$out_path/motion_correction_template_$dataset_name.csh
            cp $templates_path/motion_correction_template.csh $motion_script
            sed -i "s#Xmatlab_path#${matlab}#g" $motion_script
            sed -i "s#Xlog_dir#${out_path}#g" $motion_script
            sed -i "s#Xsoftware_path#${spm_path}#g" $motion_script
            sed -i "s#Xuse_old_moco#${use_old_moco}#g" $motion_script
            sed -i "s#Xmoco_to_middle_run#${moco_to_middle_run}#g" $motion_script
            sed -i "s#Xfunc_dir#$(dirname $last_func__sub)#g" $motion_script
            sed -i "s#Xslicetime_prefix#${slicetime_prefix}#g" $motion_script
            sed -i "s#Xparameter_dir#${motion_params_dir__sub}#g" $motion_script 

            if (( $sub==1 && $sess==1 )); then
                printf "\n Study-specific motion script: $motion_script\n"
            fi

            # TODO:remove mrrc_plot_motion_parameters from mrrc_motioncorrection_wrapper.m
            $motion_script 

        else printf "(SKIPPED - already exists) " tee -a $log_file
        fi
    else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
    fi


    } || { # catch
    printf "Error during motion correction, stopping here.\
        \nA common issue is connecting without a display set. Check that you\'ve connected with ssh -X. \n"
    exit
    }

done
done
printf "\n"


#############################################################
# *** STEP 5. Linear Registration

printf "\n\n*** STEP 5. Linear Registration (mean func -> anat)\n This step takes ~1 min/scan\n Registering scan:" tee -a $log_file

for ((sub=1; sub<=$n_subs; sub++)); do
for ((sess=1; sess<=$n_sess; sess++)); do

    {
    sub_ID=$(sed "${sub}q;d" $sub_IDs)
    if [ "$do_session" == true ]; then
        sess_ID_grep_str="/$ses_bids_prefix$sess"
    fi
    printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file

    anat_img__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $anat_names)
    if [ -f "$anat_img__sub" ]; then
        anat_stripped__sub=$(ls ${anat_img__sub%%.*}*${stripped_suffix} 2>/dev/null)
        first_func__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $func_names | head -1)
        if [ -f "$first_func__sub" ]; then
            mean_func__sub="$(ls $(dirname $first_func__sub)/${mean_func_prefix}*nii* 2>/dev/null)"
            linear_transform__sub=$(ls $(dirname $first_func__sub)/*${linear_trans_suffix}${linear_trans_ext} 2>/dev/null)

            if [ ! -f "${linear_transform__sub}" ]; then
                
                linear_setup_file=$out_path/linear_setup_$dataset_name
                cp $templates_path/linear_setup_template $linear_setup_file
                sed -i "s#Xstripped_img#${anat_stripped__sub}#g" $linear_setup_file
                sed -i "s#Xmean_func#${mean_func__sub}#g" $linear_setup_file
                sed -i "s#Xlinear_trans_suffix#${linear_trans_suffix}${linear_trans_ext}#g" $linear_setup_file
                    
                if (( $sub==1 )); then
                    printf "\n Study-specific linear registration setup file: $linear_setup_file\n"
                fi
                
                bis_makebatch.tcl -odir $(dirname $first_func__sub) -setup $linear_setup_file -makefile $out_path/linearregisteration.make

                make -f $out_path/linearregisteration.make -j $n_jobs
                # TODO: javid's version uses linearbrainregister.tcl--is there a reason why?

            else printf "(SKIPPED - already exists) " tee -a $log_file
            fi
        else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
        fi
    else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
    fi


    } || { # catch
    printf "Error during linear registration, stopping here.\
        \nA common issue is connecting without a display set. Check that you\'ve connected with ssh -X. \n"
    exit
    }

done
done
printf "\n"



#############################################################
# *** STEP 6. Final Check Of Previous Steps

transform_img_for_check=0

printf "\n\n*** STEP 6. Final Check Of Previous Steps " tee -a $log_file
printf "\n IMPORTANT: Visual inspection of the previous steps is strongly encouraged before proceeding.\
\n If you have not completed visual inspection, enter \"no\" and you will have the option to create files for visual inspection."
read -rep $'\n Proceed to final study processing? (enter \"yes\"/\"no\") \n > ' response_step7

if [[ "$response_step7" =~ "no" ]]; then
    printf " Okay, will NOT finish processing.\n\n If you need help with visual inspection, we can now transform each mean functional image to common space.\n If this looks good, it will mean the above steps succeeded."
    read -rep $'\n Create transformed mean functionals? (enter \"yes\"/\"no\")\n > ' response_transform
    if [[ "$response_transform" =~ "yes" ]]; then transform_img_for_check=true
    elif [[ "$response_transform" =~ "no" ]]; then printf " Okay, stopping without transforming mean functional.\n" tee -a $log_file; exit 0
    else printf " User did not respond yes or no. Stopping without transforming mean functional.\n" tee -a $log_file; exit 0
    fi
elif [[ "$response_step7" =~ "yes" ]]; then printf "\n Okay, continuing to final study processing.\n" tee -a $log_file
else printf " User did not respond yes or no. Stopping.\n" tee -a $log_file; exit 0
fi


if [ "$transform_img_for_check" == true ]; then
    printf " Okay, transforming mean functionals.\n\n Transforming sub " tee -a $log_file
    
    for ((sub=1; sub<=$n_subs; sub++)); do
    for ((sess=1; sess<=$n_sess; sess++)); do
        sub_ID=$(sed "${sub}q;d" $sub_IDs)
        if [ "$do_session" == true ]; then
            sess_ID_grep_str="/$ses_bids_prefix$sess"
        fi
        printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file
       
        anat_img__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $anat_names)
        if [ -f "$anat_img__sub" ]; then
            nonlinear_transform__sub=$(ls $(dirname $anat_img__sub)/[^I]*${nonlinear_final_pass}*${nonlinear_trans_ext} 2>/dev/null)
            
            first_func__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $func_names | head -1)
            if [ -f "$first_func__sub" ]; then
                mean_func__sub="$(ls $(dirname $first_func__sub)/${mean_func_prefix}*nii* 2>/dev/null)"
                linear_transform__sub=$(ls $(dirname $first_func__sub)/*${linear_trans_suffix}${linear_trans_ext} 2>/dev/null)
                mean_in_ref__sub="$(dirname $first_func__sub)/${mean_func_in_ref_prefix}$(basename $mean_func__sub)"
                
                if [[ ! -f $mean_in_ref__sub ]]; then
                    bis_resliceimage.tcl -inp $reference_img -inp2 $mean_func__sub -inp3 $nonlinear_transform__sub -inp4 $linear_transform__sub -out $mean_in_ref__sub
                else printf "(SKIPPED - already exists) " tee -a $log_file
                fi
            else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
            fi
        else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
        fi


    done
done
    printf "\n Created transformed images for inspection in subject folders (see files beginning with \"${mean_func_in_ref_prefix}\").\
        \n Check that these look reasonable and align with the reference image $reference_img.\n"
    exit 0
fi



#############################################################
# *** STEP 7. Final Study Processing

printf "\n\n*** STEP 7. Final Study Processing (GLM, Connectivity, etc)\n This step takes ~5 min/scan, plus 10 min per anatomical (if not already inverted)\n Processing scan:" tee -a $log_file

results_dir="$out_path/results"
if [ ! -d "${results_dir}" ]; then mkdir $results_dir; fi

#source $scripts_path/modify_study_setup_files.sh
#source $scripts_path/create_master_study_setupfile.sh

# Make study-specific edits - subject-specific edits will be made later in the main

setupfile=$out_path/study_setupfile_${dataset_name}.xmlg
cp $templates_path/study_setupfile_template.xmlg $setupfile

sed -i "s#Xdataset_name#${dataset_name}#g" $setupfile
sed -i "s#Xreference_img#${reference_img}#g" $setupfile
sed -i "s#Xwm_csf_img#${wm_csf_img}#g" $setupfile
sed -i "s#Xidentity_matrix#${identity_mat}#g" $setupfile
sed -i "s#Xtr#${tr}#g" $setupfile
sed -i "s#Xn_slices#${n_slices}#g" $setupfile
sed -i "s#Xn_frames#${n_frames}#g" $setupfile
sed -i "s#Xoutput_dir#${results_dir}#g" $setupfile
sed -i "s#Xparcellation#${parcellation}#g" $setupfile
sed -i "s#Xtemporal_sigma#${temporal_sigma}#g" $setupfile
sed -i "s#Xgsr#${do_GSR}#g" $setupfile


for ((sub=1; sub<=$n_subs; sub++)); do
  for ((sess=1; sess<=$n_sess; sess++)); do
    
    sub_ID=$(sed "${sub}q;d" $sub_IDs)
    if [ "$do_session" == true ]; then
        sess_ID_grep_str="/$ses_bids_prefix$sess"
        sess_ID="$ses_bids_prefix$sess"
    fi
    printf "\n $sub_ID$sess_ID_grep_str " tee -a $log_file
  
    func_names__sub=($(grep "/$sub_ID$sess_ID_grep_str/" $func_names))
    last_result__sub="$(ls $results_dir/*${sub_ID}*${sess_ID}_${#func_names__sub[@]}_*${processing_type}*txt 2>/dev/null)"
    
    if [ ! -f "$last_result__sub" ]; then
    
    { 
    anat_img__sub=$(grep "/$sub_ID$sess_ID_grep_str/" $anat_names)
    if [ -f "$anat_img__sub" ]; then
        nonlinear_transform__sub=$(ls $(dirname $anat_img__sub)/[^I]*${nonlinear_final_pass}*${nonlinear_trans_ext} 2>/dev/null)
        nonlinear_transform_inverse__sub=$(ls $(dirname $anat_img__sub)/Inverse* 2>/dev/null)

        first_func__sub=${func_names__sub[1]}
        if [ -f "${first_func__sub}" ]; then
            linear_transform__sub="$(ls $(dirname $first_func__sub)/*${linear_trans_suffix}${linear_trans_ext} 2>/dev/null)"

            setupfile__sub=$out_path/study_setupfile_${dataset_name}__subject.xmlg
            
            cp $setupfile $setupfile__sub
            sed -i "s#XsubjectID#${sub_ID}${sess_ID}#g" $setupfile__sub
            sed -i "s#Xanat#${anat_img__sub}#g" $setupfile__sub
            sed -i "s#Xnonlinear_transform#${nonlinear_transform__sub}#g" $setupfile__sub
            sed -i "s#Xlinear_transform#${linear_transform__sub}#g" $setupfile__sub
            sed -i "s#Xnruns#${#func_names__sub[@]}#g" $setupfile__sub

            if [ -f $nonlinear_transform_inverse__sub ]; then
                sed -i "s#Xinverse_nl_transform#\n${nonlinear_transform_inverse__sub}#g" $setupfile__sub
            else
                sed -i "s#Xinverse_nl_transform##g" $setupfile__sub
            fi


            for ((func_no=0; func_no<${#func_names__sub[@]}; func_no++)); do
                func_name=${func_names__sub[$func_no]}

                motion_corr_func__scan="$(ls $(dirname $func_name)/${motion_corr_prefix}*$(basename $func_name)* 2>/dev/null)"
                motion_params__scan="$(ls $(dirname $func_name)/${motion_params_topdir}/*$(basename ${func_name%.*})*${motion_params_suffix} 2>/dev/null)"
                
                if (( $func_no==0 )); then separator=""
                else separator="\n\n\n"
                fi
                
                sed -i "s#Xfunc_and_motion#${separator}${motion_corr_func__scan}\n${motion_params__scan}Xfunc_and_motion#g" $setupfile__sub
            done

            cp $setupfile__sub $tmp_file
            sed -i "s#Xfunc_and_motion##g" $tmp_file
            cp $tmp_file $setupfile__sub
            if (( $sub==1 )) ; then
                printf "\n Tailored setupfile: $setupfile__sub\n"
            fi
            

                bis_fmrisetup.tcl $setupfile__sub ${processing_type}
          
           
        else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
        fi
    else printf "(SKIPPED - **MISSING ORIGINAL FILE**) " tee -a $log_file
    fi
    
    } || { # catch
    printf "\nError while running final setupfile, stopping here.\
        \nSee above error messages. Files may have been unable to be loaded or unable to be found (see X* in the setupfile). The setupfile can be examined here: $setupfile__sub.\
        \nYou can also re-run this script to create transformed images for visual inspection in Step 6.\n"
    exit
    }

    else printf "(SKIPPED - already exists) " tee -a $log_file
    fi
    


done
done


printf "\n Success!!! All processing complete.\n" tee -a $log_file






