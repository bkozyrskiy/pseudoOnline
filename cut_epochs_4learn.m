function [ eegTRP1, eegNT] = cut_epochs_4learn(datapath,fs,window_size,baseline_time,start_rp_time,end_rp_time)
%loaddata Cut epochs frow semi-raw data

[data,eog,mask] = loaddata(datapath);
[~,grad] = gradient(data);
% [irrelevant_mask] = search_irrelevant_data(mask,data);

starts = find(mask == 12);
ends = find(mask == 13);
starts = starts(1:size(ends,2));

nontarget_epochs1 = [];nontarget_epochs2 = [];rp1_epochs = [];
for i =1:size(ends,2)
    [tmp_nontarget_epochs1,tmp_nontarget_epochs2,tmp_rp1_epochs] = ...
        process_interval(data(starts(i):ends(i),:),grad(starts(i):ends(i),:),mask(starts(i):ends(i)),eog(starts(i):ends(i)),window_size,fs, ...
        baseline_time,start_rp_time,end_rp_time);
    if ~isempty(tmp_nontarget_epochs1)
        nontarget_epochs1 = cat(3,nontarget_epochs1,tmp_nontarget_epochs1);
    end
    
    if ~isempty(tmp_nontarget_epochs2)
        nontarget_epochs2 = cat(3,nontarget_epochs2,tmp_nontarget_epochs2);
    end
    
    if ~isempty(tmp_rp1_epochs)
        rp1_epochs = cat(3,rp1_epochs,tmp_rp1_epochs);
    end
end

eegTRP1 = rp1_epochs;
nt1 = nontarget_epochs1(:,:,randperm(size(nontarget_epochs1,3)));
nt2 = nontarget_epochs2(:,:,randperm(size(nontarget_epochs2,3)));
eegNT= cat(3,nt1,nt2);

% [params, spec, sens, acc, auc] = test_loading_alg(cat(3,rp1_epochs(:,:,1:250),rp2_epochs),cat(3,nt1,nt2),fs);

end

function [nontarget_epochs1,nontarget_epochs2,rp1_epochs] = process_interval(interval_data,grad,epoch_mask,eog,w_size,fs,baseline_time,start_rp_time,end_rp_time)
    bline_width = baseline_time*fs/1000;
    nontarget_epochs1 = [];
    nontarget_epochs2 = [];
    rp1_epochs = [];
    rp_length = 2;%RP length - 2seconds
    if(sum(epoch_mask) == 35 && (find(epoch_mask == 10,1) > (rp_length*fs))) % 12+13+10, so interval contain movement,
        %And this movement 3s after beginning of the interval
        %We have only one rp2 epoch in whole interval
        movement = find(epoch_mask==10);      
        start_rp1_data = movement + start_rp_time * fs /1000;
        end_rp1_data = movement + end_rp_time * fs /1000;
        rp1_epochs = cat(3,rp1_epochs,make_epochs(interval_data(start_rp1_data-bline_width+1:end_rp1_data,:), ... %additional window for baseline
            grad(start_rp1_data-bline_width+1:end_rp1_data,:),eog(start_rp1_data-bline_width+1:end_rp1_data),w_size,bline_width));
        
        if ( movement - (2000 *fs/1000) - (1000*fs/1000)) > (bline_width + w_size) %We throw out 1s after interval beginning and 2s before movement
            % 10 minus 2s of rp and 1s after 12 label (one window for classifier
            %one window for baseline)
            start_rel_data = (1000*fs/1000); %We will use data 1s from 12
            end_rel_data = movement - (2000 *fs/1000);  %We will use data 2s before movement
            tmp_nontarget_epochs1 =  make_epochs(interval_data(start_rel_data:end_rel_data,:), ...
                grad(start_rel_data:end_rel_data,:),eog(start_rel_data:end_rel_data),w_size,bline_width);
            if(~isempty(tmp_nontarget_epochs1))
                nontarget_epochs1 = cat(3,nontarget_epochs1,tmp_nontarget_epochs1);
            end
        end
%         if (size(interval_data,1) - (movement +(1000 *fs/1000)) - (1000*fs/1000)) > (bline_width + w_size) %We throw out 1s after movement and 1 second before interval end
%             start_rel_data = (movement + 1000*fs/1000); %We will use data 1s after 10 label
%             end_rel_data = size(interval_data,1) - (1000 *fs/1000);  %We will use data 1s before 13 label
%             
%             tmp_nontarget_epochs1 = make_epochs(interval_data(start_rel_data:end_rel_data,:), ...
%                 grad(start_rel_data:end_rel_data,:), w_size,bline_width);
%             if(~isempty(tmp_nontarget_epochs1))
%                 nontarget_epochs1 = cat(3,nontarget_epochs1,tmp_nontarget_epochs1);
%             end
%         end
    else
        start_rel_data = (1000*fs/1000); %We will use data 1s from 12
        end_rel_data = size(interval_data,1);
        
        [nontarget_epochs2] = make_epochs(interval_data(start_rel_data:end_rel_data,:), ...
            grad(start_rel_data:end_rel_data,:),eog(start_rel_data:end_rel_data), w_size,bline_width);
    end
        
end

function [epochs] = make_epochs(data,grad,eog,w_size,bline_width) 
    epochs= [];
    for i = size(data,1):-w_size:(bline_width+w_size) %last window for baseline
        tmp_epoch = data(i-w_size+1:i,:);
        baseline = mean(data(i-(bline_width+w_size) + 1:i-w_size,:),1);
        bcorrected_epoch = tmp_epoch - repmat(baseline,size(tmp_epoch,1),1);
        if ~isempty(tmp_epoch)
            if is_relevant(tmp_epoch,grad(i-(bline_width+w_size) + 1:i,:),bcorrected_epoch,eog(i-(bline_width+w_size) + 1:i))
                epochs = cat(3,epochs,bcorrected_epoch); 
            end
        end
    end
end


function [is_relevant] = is_relevant(data,grad,baseline_corrected,eog)
    baseline_blow = sum(max(abs(baseline_corrected),[],1) > 70) > 3;
    grad_blow = sum(mean(abs(grad),1) > 2) > 2;
    eog_blow = max(abs(eog)) < 200;
    is_relevant = ~(baseline_blow | grad_blow) | eog_blow; 
end


function [params, spec, sens, acc, auc] = test_loading_alg(eegT, eegNT,fs)
    X1 = get_feats(eegT, fs, 0, 0.4);
    X0 = get_feats(eegNT, fs, 0, 0.4);
    [params, spec, sens, acc, auc] = train(X1,X0);
end

function [params, spec, sens, acc, auc] = train(X1,X0)
%
% X0: [Nsamples0 * Nfeats]
% X1: [Nsamples1 * Nfeats]
%

N0 = size(X0, 1);
N1 = size(X1, 1);
X = [X0;X1]; 
Y = [ones(1,N0) 2*ones(1,N1)]';

nfolds = 20;
CV = cvpartition(Y, 'k', nfolds);
meanAucX = linspace(0,1,ceil(size(Y,1)/5));
meanAucYtr = zeros(size(meanAucX));
meanAucYtst = zeros(size(meanAucX));

for i = 1:CV.NumTestSets
    trIdx = CV.training(i);
    tstIdx = CV.test(i);
    Ytr = Y(trIdx, :);
    Ytst = Y(tstIdx, :);
            
    Xtr = X(trIdx, :);  
    Xtst = X(tstIdx, :);
    
    [prin_comp,Xtr] = princomp(Xtr);
    Xtr = Xtr(:,1:150);
    Xtst = Xtst*prin_comp(:,1:150);

%     [Xtr, transform_matrix] = compute_mapping(Xtr, 'LPP', 80);
%     Xtst = Xtst*transform_matrix.M;
    
    
    %chosing R2 relevant feats
%     ind_of_correl_feats = find_meaningful_feats(Xtr,Ytr,50);
%     Xtr = Xtr(:,ind_of_correl_feats);
%     Xtst  = Xtst(:,ind_of_correl_feats);
    
    N0tr = sum(Ytr == 1);
    N1tr = sum(Ytr == 2);
    N0tst = sum(Ytst == 1);
    N1tst = sum(Ytst == 2);

    % train
    obj = train_shrinkage(Xtr, Ytr);
    W(:,:,i) = obj.W;
    %W(:,:,i) = rand(size(obj.W))*0.02-0.01;
    
    % calc acc on train sample
    Q = Xtr*W(:,:,i);    
    Q0 = Q(Ytr == 1);
    Q1 = Q(Ytr == 2);
  
    [aucXtr,aucYtr, ~, auc_tr(i)] = perfcurve([ones(N1tr,1); zeros(N0tr,1)], [Q1; Q0], 0);
    [aucXtr, index]=unique(aucXtr);
    meanAucYtr = meanAucYtr + interp1(aucXtr,aucYtr(index),meanAucX);
    
    % test
    Q = Xtst*W(:,:,i);
    Q0 = Q(Ytst == 1);
    Q1 = Q(Ytst == 2);
%     sens_tst(i) = length(find(Q1 <= th_opt(i))) / N1tst;
%     spec_tst(i) = length(find(Q0 > th_opt(i))) / N0tst;    
%     acc_tst(i) = (sens_tst(i) * N1tst + spec_tst(i) * N0tst) / (N1tst + N0tst);
    [aucXtst,aucYtst, ~, auc_tst(i)] = perfcurve([ones(N1tst,1); zeros(N0tst,1)], [Q1; Q0], 0);
    [aucXtst, index]=unique(aucXtst);
    meanAucYtst = meanAucYtst + interp1(aucXtst,aucYtst(index),meanAucX);
    
    [~,~, ~, auc_const(i)] = perfcurve([ones(N1tst,1); zeros(N0tst,1)], [zeros(N1tst,1); zeros(N0tst,1)], 0);
    
end

% spec.tr = [mean(spec_tr) std(spec_tr)];
% sens.tr = [mean(sens_tr) std(sens_tr)];
spec.tr = 0;
sens.tr = 0;
acc.tr = 0;
% spec.tst = [mean(spec_tst) std(spec_tst)];
% sens.tst = [mean(sens_tst) std(sens_tst)];
% acc.tst = [mean(acc_tst),std(acc_tst)];
spec.tst = 0;
sens.tst = 0;
acc.tst = 0;
auc.x = meanAucX;
auc.tr.square = [mean(auc_tr) std(auc_tr)];
auc.tr.y = meanAucYtr/nfolds;
auc.tst.square = [mean(auc_tst) std(auc_tst)];
auc.tst.y = meanAucYtst/nfolds;
auc.const.square = [mean(auc_const) std(auc_const)];
auc.all = 0;


params.W = mean(W, 3);
%params.th = mean(th_opt);

end