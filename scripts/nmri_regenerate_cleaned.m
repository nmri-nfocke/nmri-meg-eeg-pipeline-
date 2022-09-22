function [ subject ] = nmri_regenerate_cleaned(subject, workmode, backup, params)
%[ subject ] = nmri_regenerate_cleaned(subject, workmode, backup, params)
%  
% This function will re-generate the cleaned dataset with the information
% stored in the backup struct
% if this is not passed to the function, will try to locate the most recent
% backup info from the subject.backup field, or the files
% if multipel backups are found, will promt for the user to decide
% 
% Note: ICA-cleaning will have to be re-run later
% 

% subject       =   subject structure of cleaned subject, i.e. the one that was
%                   processed before.
% backup        =   backup struct (as generated by nmri_backup_cleaning_marking)
% workmode      =   which files to re-generate
%                   'all': dws-filt + cleaned
%                   'cleaned': just cleaned
%
% params        =   anaylsis parameter struct (optional, will search for
%                    analysis_params.m if not set)

% written by NF 10/2019


% check the call
if ~exist('subject','var')
 error('Need a valid subject struct to work with')
end

if ~exist('workmode','var') || ~any(strcmp(workmode,{'all','cleaned'}))
 error('Workmode not set, or not valid (''all'' or ''cleaned'')')
end


% call the subject and params include
nmri_include_read_ps

% Get the modality-specific analysis params
[ params ] = nmri_get_modality_params( params, subject.dtype );


% now check the backup info
if (~exist('backup','var') ) 
 all_backups=[];
 % parse the subject struct
 if isfield(subject,'backup') && isfield(subject.backup,'date')
  % seem to have legitimate info
  all_backups=subject.backup;
 end
 % now parse the backup dir
 bdir=fullfile(subject.analysis_dir,subject.id,'backup');
 if exist(bdir,'dir')
  % parse all files and check date
  all_f=dir(bdir);
  all_m={};
  for i=1:size(all_f,1)
   if ~strcmp(all_f(i).name(1),'.') && ~all_f(i).isdir && length(all_f(i).name)>4 && strcmp(all_f(i).name(end-3:end),'.mat')
    all_m=[all_m {fullfile(bdir,all_f(i).name)}];
   end
  end
  if ~isempty(all_m)
   loaded=nf_load_mats_struct(all_m,'backup');
  else
   loaded=[];
  end
  % now merge with other
  for i=1:length(loaded)
   % find date
   if isfield(loaded(i),'date')
    this_date=loaded(i).date;
   else
    % try to guess from filename
    [~,fi,~]=fileparts(loaded(i).loaded_from);
    parts=strsplit(fi,'_');
    % check if convertable
    [~,isnum]=str2num(parts{end});
    if isnum
     this_date=parts{end};
    else
     this_date='?';
    end
   end
   if ~isfield(all_backups,'date') || ~strcmp([all_backups(:).date],this_date)
    % add to all_backup
    idx=length(all_backups)+1;
    all_backups(idx).date=this_date;
    all_backups(idx).data=loaded(i);
    all_backups(idx).file=loaded(i).loaded_from;
   end
  end
 end
 
 if length(all_backups)>1
  % prompt the user
  manselect=listdlg('Name',['Found >1 possibility, please pick one'],'SelectionMode','single','ListSize',[300 (50+(length(all_backups)*10))],'ListString',{all_backups.date});
  if (~isempty(manselect))
   backup=all_backups(manselect);
  end
 elseif length(all_backups)==1
  backup=all_backups;
 else
  error('Backup struct not given, and no backup file or backup subject struct could be detected. Cannot continue.')
 end
end



% deal with dws-filt data
if strcmp(workmode,'all')
 if isfield(subject,'dws_filt_dataset') && exist(subject.dws_filt_dataset,'file')
  delete(subject.dws_filt_dataset)
 end
end

if strcmp(workmode,'all')
 % now re-run pre-processing (you may have changed analysis_params)
 [subject, data]=nmri_preproc(subject);
 % always attempt to read markers
 subject=nmri_read_markers(subject);
else
 % load the dws-filt
 if (~isfield(subject,'dws_filt_dataset') || ~exist(subject.dws_filt_dataset,'file'))
  error('Filtered and downsampled dataset not specified, run nmri_preproc first')
 else
  disp(['Loading raw dataset: ' subject.dws_filt_dataset ])
  load(subject.dws_filt_dataset,'data');
 end
end

% deal with cleaned data
if any(strcmp(workmode,{'all','cleaned'}))
 if isfield(subject,'clean_dataset') && exist(subject.clean_dataset,'file')
  delete(subject.clean_dataset)
 end
 if isfield(subject,'cleanICA_dataset') && exist(subject.cleanICA_dataset,'file')
  delete(subject.cleanICA_dataset) % skip this line, if no ICA was done
 end
end

if isfield(backup,'data')
 backup=backup.data;
end

% now re-generate the markings/cleaning from backup
if isfield(backup,'evt_timings_seconds') && isfield(backup,'evt_timings_sample') && isfield(backup,'evt_IDs')
 % regenerate the events
 subject.evt_timings_seconds=backup.evt_timings_seconds;
 subject.evt_timings_sample=backup.evt_timings_sample;
 subject.evt_IDs=backup.evt_IDs;
else
 disp(['No event_markings in the backup for subject=' subject.id])
end

% make an empty trialmarkings
data.trial_markings=cell(length(data.time),4);
 % col1: sleep
 % col2: technical
 % col3: event
 % col4: rest/stimulation
 
data.trial_markings_sampleinfo=cell(length(data.time),2);
 % col1: sampleinfo start/stop
 % col2: seconds start/stop
for i=1:length(data.time)
 data.trial_markings_sampleinfo{i,1}=data.sampleinfo(i,:);
 data.trial_markings_sampleinfo{i,2}=data.sampleinfo(i,:)/data.fsample;
end


if isfield(backup,'trial_markings')
 % now find the markings from backup 
 for i=1:size(backup.trial_markings)

 % match the time in the new data
 maxmin=1; % want a 1 second match
 sel_trial=[];
 for ii=1:length(data.time)
  minval=min(abs(data.time{ii}-backup.trial_markings_sampleinfo{i,2}(1)));
  if minval<maxmin
   maxmin=minval;
   sel_trial=ii;
  end
 end
 
 if ~isempty(sel_trial)
  % copy the marking
  data.trial_markings(sel_trial,1:size(backup.trial_markings(i,:),2))=backup.trial_markings(i,:);
 end
end

fprintf('Re-generated valid trial markings for vigilance=%d\n',sum(~cellfun(@(x) isempty(x),data.trial_markings(:,1))))
fprintf('Re-generated valid trial markings for technical=%d\n',sum(~cellfun(@(x) isempty(x),data.trial_markings(:,2))))
fprintf('Re-generated valid trial markings for events=%d\n',sum(~cellfun(@(x) isempty(x),data.trial_markings(:,3))))
fprintf('Re-generated valid trial markings for stimulation=%d\n',sum(~cellfun(@(x) isempty(x),data.trial_markings(:,4))))



% no deal with bad_channels

if isfield(backup,'bad_channels')
 % these are bad for sure
 data.bad_channels=backup.bad_channels;
end
fprintf('Re-generated bad_channnels, N=%d\n',length(data.bad_channels))


% now safe the new cleaned file

nmri_write_dataset(subject.clean_dataset,data,subject);

% and stamp, if we have at least some info (> 10 trials with technical
% info)
if (sum(~cellfun(@(x) isempty(x),data.trial_markings(:,2)))>10) 
 subject=nmri_stamp_subject(subject,'artifactrejection',params);
end


if isfield(params,'useICA_clean') && params.useICA_clean==1 
 if isfield(subject,'cleanICA_dataset') &&  exist(subject.cleanICA_dataset,'file')
  disp('Deleting ICA dataset...')
  delete(subject.cleanICA_dataset);
 end
 if (isfield(subject,'ICA_components') && exist(subject.ICA_components,'file'))
  disp('Deleting ICA components...')
  delete(subject.ICA_components);
 end
 job_title='artifactrejectionICA_estimate';
 sge_dir=nmri_qsub('nmri_artifactrejection_estimateICA',subject,job_title);
 fprintf('Submitted job=%s of subject=%s and exam_id=%s, sge_dir=%s\n',job_title,subject.id,subject.exam_id,sge_dir)
end


fprintf('...done\n')



end



