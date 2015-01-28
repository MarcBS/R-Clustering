function doSingleTest( LHs, clusterId, bound_GC, win_len, W, W2, features, tolerance, GT, doEvaluation, clus_type )
%%
%   Applies a single GC test.
%
%   LHs:        likelihoods resulting from the previously applied 
%               clustering and/or adwin. This variable is a cell array with
%               1 or 2 positions, depending on the methods applied before.
%   clusterId:  clustering ids for each sample. 
%               This variable is a cell array with
%               1 or 2 positions, depending on the methods applied before.
%   win_len:    window length used for the linking of the GC samples
%   W:          weighting term applied on the pair-wise term (increas in
%               each iteration).
%               W > 0
%   W2:         weighting term applied to the LHs of the two clustering
%               methods (only if there are 2 elements in LHs).
%               0 <= W2 <= 1
%   tolerance:  tolerance value for the evaluation
%   GT:         events starting points on the ground truth.
%   doEvaluation: plot the evaluation final results
%
%%%%%%
    nSamples = size(features,1);
    
    dists = pdist(features);
    % dists = normalizeHistograms(dists);
    dists = squareform(dists);

    if(length(LHs) == 2 && length(clusterId) == 2)
        %% Apply weighting between the clustering methods
        nClus = 2;
        %[~, start_clus{1}, ~] = getEventsFromLH(LHs{1});
        %[~, start_clus{2}, ~] = getEventsFromLH(LHs{2});
        [recClus,precClus,accClus,fMeasureClus]=Rec_Pre_Acc_Evaluation(GT,bound_GC{1},nSamples,tolerance);
        [recClus2,precClus2,accClus2,fMeasureClus2]=Rec_Pre_Acc_Evaluation(GT,bound_GC{2},nSamples,tolerance);
        LH_Clus = joinLHs(LHs, clusterId, W2);
    elseif(length(LHs) == 1 && length(clusterId) == 1)
        nClus = 1;
        %[~, start_clus{1}, ~] = getEventsFromLH(LHs{1});
        [~, ~, ~, fMeasureClus]=Rec_Pre_Acc_Evaluation(GT,bound_GC{1},nSamples,tolerance);
        LH_Clus = LHs{1};
    else
        error('LHs and start_clus variables must be cells with the same length and 2 terms as maximum!');
    end
    
    %% Execute Graph-Cuts
    LH_GC = buildGraphCuts(LH_Clus, features, win_len, W, dists); 
    
    %% Convert LH results on events separation (on GC result)
    [ labels, start_GC, num_clusters ] = getEventsFromLH(LH_GC);
    
    [recGC,precGC,accGC,fMeasureGC]=Rec_Pre_Acc_Evaluation(GT,start_GC,nSamples,tolerance);

    disp(' ');
    if(doEvaluation)
        if(nClus == 2)
            disp('-------- Results Clustering --------');
            disp(['Precision: ' num2str(precClus)]);
            disp(['Recall: ' num2str(recClus)]);
            disp(['F-Measure: ' num2str(fMeasureClus)]);
            disp(' ');
            disp('-------- Results Adwin --------');
            disp(['Precision: ' num2str(precClus2)]);
            disp(['Recall: ' num2str(recClus2)]);
            disp(['F-Measure: ' num2str(fMeasureClus2)]);
        elseif(nClus == 1);
            disp(['-------- Results ' clus_type ' --------']);
            disp(['Precision: ' num2str(precClus)]);
            disp(['Recall: ' num2str(recClus)]);
            disp(['F-Measure: ' num2str(fMeasureClus)]);
        end
        disp(' ');
        disp('-------- Results Graph-Cuts --------');
        disp(['Precision: ' num2str(precGC)]);
        disp(['Recall: ' num2str(recGC)]);
        disp(['F-Measure: ' num2str(fMeasureGC)]);
    end
    disp(['Number of events: ' num2str(num_clusters)]);
    disp(['Mean frames per event: ' num2str(length(labels)/num_clusters)]);
    disp(' ');

end

