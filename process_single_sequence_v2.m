function [events, results] = process_single_sequence_v2(folder, params)

%% Load paths
addpath('Adwin;Data_Loading;Evaluation;Features_Preprocessing');
addpath('GCMex;GraphCuts;PCA;Tests;Utils;SpectralClust');

load_features = true;

%% Parameters loading
fichero = params.files_path;
formats = params.formats;

doEvaluation = params.doEvaluation;
if(doEvaluation);
    GT = params.GT;
else
    GT = [];
end

%% Clustering parameters
methods_indx= params.methods_indx;
cut_indx= params.cut_indx_use;
paramsPCA.usePCA_Clustering = true;

%% R-Clustering parameters
clus_type = params.clus_type;

%% GraphCuts parameters
evalType = 1;
W_unary = params.W_unary;
W_pairwise = params.W_pairwise;
paramsfeatures.type = 'CNN';
paramsPCA.minVarPCA=0.95;
paramsPCA.standarizePCA=false;
paramsPCA.usePCA_Clustering = true;
plotFigResults = false;

%% Adwin parameters
pnorm = 2;
confidence = 0.1;
paramsPCA.usePCA_Adwin = true;

%% GraphCuts parameters
paramsPCA.usePCA_GC = false;
window_len = 11;

%% Evaluation parameters
tol=5; % tolerance for the final evaluation

%% Grid Search
tot_res = [];

%% Build paths for images, features and results
[~, folder_name, ~] = fileparts(folder);
path_features = [params.features_path '/CNNfeatures/CNNfeatures_' folder_name '.csv'];
path_features_PCA = [params.features_path '/CNNfeatures/CNNfeaturesPCA_' folder_name '.mat'];
if(params.semantic_type == 2 || params.semantic_type == 4) % IMAGGA
    path_semantic_features = [params.features_path '/SemanticFeatures/SemanticFeatures_' folder_name '.mat'];
elseif(params.semantic_type == 3) % LSDA
    path_semantic_features = [params.features_path '/SemanticFeatures/SemanticFeaturesLSDA_' folder_name '.mat'];
end

%% Images
files_aux=dir([fichero '/*' formats]);
count = 1;
files = struct('name', []);
for n_files = 1:length(files_aux)
    if(files_aux(n_files).name(1) ~= '.')
        files(count).name = files_aux(n_files).name;
        count = count+1;
    end
end
Nframes=length(files);

%% Global Features
if strcmp(paramsfeatures.type, 'CNN')
    if(load_features)
        features = csvread(path_features); %load(path_features);
        [features_norm] = signedRootNormalization(features);
    end
    if(size(features,1) ~= Nframes)
        error('The number of Global features does not match the number of images. TIP: remove the existent features file for re-calculation.');
    end
    [ featuresPCA, ~, ~ ] = applyPCA( features_norm, paramsPCA ) ;
    if(load_features) % if we wanted to load the stored features, then we will also store PCA features
        save(path_features_PCA, 'featuresPCA');
    end
end

%% Semantic Features
if(params.use_semantic)
    if(load_features)
        load(path_semantic_features); % 'tag_matrix'
    end
    tag_matrix_GC = tag_matrix;
    if(size(tag_matrix,2) ~= Nframes)
        error('The number of Semantic features does not match the number of images. TIP: remove the existent features file for re-calculation.');
    end
    if(params.semantic_type == 3)
        tag_matrix = [];
    end
else
    tag_matrix_GC = [];
    tag_matrix = [];
end

%% CLUSTERING
LH_Clus={};
start_clus={};
previousMethods = {};

%% ADWIN
if strcmp(clus_type,'Both1')||strcmp(clus_type,'Both2')
    disp(['Start ADWIN ' folder_name]);
    % PCA
    if(paramsPCA.usePCA_Adwin && strcmp(paramsfeatures.type, 'CNN'))
        [labels,dist2mean] = runAdwin([featuresPCA, tag_matrix'], confidence, pnorm);
    elseif( strcmp(paramsfeatures.type, 'CNN'))
        [features_norm] = signedRootNormalization(features);
        [labels,dist2mean] = runAdwin([features_norm, tag_matrix'], confidence, pnorm);
    end
    index=1;
    automatic2 = [];
    for pos=1:length(labels)-1
        if (labels(pos)~=labels(pos+1))>0
            automatic2(index)=pos;
            index=index+1;
        end
    end
    if (exist('automatic2','var')==0)
        automatic2=0;
    end
    
    % Normalize distances
    dist2mean = normalizeAll(dist2mean);
    bound_GC{2}=automatic2;
    LH_Clus{2}=getLHFromDists(dist2mean);
    start_clus{2}=labels;
    previousMethods{2} = 'ADWIN';
end % end Adwin

%% Clustering
if strcmp(clus_type,'Both1')||strcmp(clus_type,'Clustering')
    %% PCA
    if(paramsPCA.usePCA_Clustering &&   strcmp(paramsfeatures.type, 'CNN'))
        clust_features = [featuresPCA, tag_matrix'];
        similarities=pdist(clust_features,'cosine');
    elseif( strcmp(paramsfeatures.type, 'CNN'))
        clust_features = [features_norm, tag_matrix'];
        similarities=pdist(clust_features,'cosine');
    end
    for met_indx=1:length(methods_indx)
        method=methods_indx{met_indx};
        %% Clustering
        Z = linkage(similarities, method);
        %% Cut value
        for idx_cut=1:length(cut_indx)
            cut=cut_indx(idx_cut);
            disp(['Start Clustering ' folder_name ', method ' method ', cutval ' num2str(cut)]);
            clustersId = cluster(Z, 'cutoff', cut, 'criterion', 'distance');
            automatic = compute_boundaries(clustersId,files);
            if( strcmp(paramsfeatures.type, 'CNN'))
                P=getLHFromClustering(features_norm,clustersId);
            else
                P=getLHFromClustering(features,clustersId);
            end
            LH_Clus{1} = P;
            start_clus{1}=clustersId';
            bound_GC{1}=automatic;
            previousMethods{1} = 'AC';
            
            %% Graph Cut
            % Build and calculate the Graph-Cuts
            disp('Start GC');
            %% PCA
            if(paramsPCA.usePCA_GC && strcmp(paramsfeatures.type, 'CNN'))
                features_GC = [featuresPCA, tag_matrix_GC'];
            else
                features_GC = [features, tag_matrix_GC'];
            end
            [features_GC, ~, ~] = normalize(features_GC);
            [ labels, start_GC, results ] = doSingleTest(LH_Clus, start_clus, bound_GC ,window_len, W_unary, W_pairwise, features_GC, tol, GT, doEvaluation, previousMethods);
            tot_res = [tot_res; results];
            close all;
        end %end cut
    end %end method
    clearvars LH_Clus start_clus
end %end if clustering || both1

%% Merge small segments to the most similar adjacent ones
if (isfield(params,'min_length_merge') && params.min_length_merge > 1)
    s = 1;
    num_frames = length(labels);
    finished = false;
    while (~finished)
        % Measure length of segments
        id_segments = unique(labels);
        num_segments = length(id_segments);
        segm_lengths = zeros(1,num_segments);
        for s_iter = 1:num_segments
            segm_lengths(s_iter) = sum(labels==id_segments(s_iter));
        end
        % Finished checking all segments
        if (s == num_segments+1)
            finished = true;
        end
        
        % Find segments smaller than the defined minimum length
        if (~finished && segm_lengths(s) < params.min_length_merge)
            % Measure similarity to adjacent segments
            if (s == 1)
                % Merge to next
                tomerge = s+1;
            elseif (s == num_segments)
                % Merge to previous
                tomerge = s-1;
            else
                % Merge to most similar
                thisfeat = mean(clust_features(find(labels==id_segments(s)),:), 1);
                prevfeat = mean(clust_features(find(labels==id_segments(s-1)),:), 1);
                nextfeat = mean(clust_features(find(labels==id_segments(s+1)),:), 1);
                [dist, tomerge] = pdist2(thisfeat, [prevfeat; nextfeat], 'cosine', 'Smallest', 1);
                if (tomerge == 1)
                    tomerge = s-1;
                elseif (tomerge == 2)
                    tomerge = s+1;
                end
            end
            
            % Merge to most similar segment
            idmerge = id_segments(tomerge);
            labels(find(labels==id_segments(s))) = idmerge;
        else
            s = s+1;
        end
        
    end
    
    % Evaluate results
    [final_boundaries]=compute_boundaries(labels,num_frames);
    num_clusters = length(final_boundaries)+1;
    if(doEvaluation)
        [recMerge,precMerge,accMerge,fMeasureMerge]=Rec_Pre_Acc_Evaluation(GT,final_boundaries,num_frames,tol);
        
        disp('-------- Results small segments merging --------');
        disp(['Precision: ' num2str(precMerge)]);
        disp(['Recall: ' num2str(recMerge)]);
        disp(['F-Measure: ' num2str(fMeasureMerge)]);
    end
    disp(['Number of events: ' num2str(num_clusters)]);
    disp(['Mean frames per event: ' num2str(num_frames/num_clusters)]);
    disp(' ');
end


%% Convert output result representation
nFrames = length(labels);
events = zeros(1, nFrames); events(1) = 1;
prev = 1;
for i = 1:nFrames
    if(labels(i) == 0)
        events(i) = 0;
    else
        if(labels(i) == labels(prev))
            events(i) = events(prev);
        else
            events(i) = events(prev)+1;
        end
        prev = i;
    end
end