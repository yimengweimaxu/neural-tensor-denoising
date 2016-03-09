function [ summary ] = tensorDenoiseGridSearchCV( Y, options )
% grid search through core tensor sizes.
% options.ths - SVD threshold for setting minRank and maxRank
% options.

  %% set defaults for options structure
  if nargin < 2
    options = struct; end
  if ~isfield(options,'ths');
    options.ths = [ 0.95 0.99 ]; end
  if ~isfield(options,'coreMeasure');
    options.coreMeasure = 2; end
  if ~isfield(options,'errMeasure');
    options.errMeasure = 1; end
  if ~isfield(options,'gridStep');
    options.gridStep = 1; end
  if ~isfield(options,'r1');
    options.r1 = 10; end
  if ~isfield(options, 'resampleTrials'); % for mixing up trial counts
    options.resample = 0; end
  if ~isfield(options, 'verbose');
    options.verbose = 1; end
  if ~isfield(options, 'rng_iter');
    options.rng_iter = 0; end
  if ~isfield(options, 'method');
    options.method = 0; end

  %% LOOCV options          
  [n,t,c,r] = size(Y);
  Ys = Y;
  Ysm = mean(Ys,4,'omitnan');
  
  %% get options
  gridStep = options.gridStep;
  r1 = options.r1;
  resample = options.resample;
  verbose = options.verbose;
  rng_iter = options.rng_iter;
  method = options.method;
  minRank = options.minRank;
  maxRank = options.maxRank;
  
  %% svd / define grid search box
  N = ndims(Ysm);
  ysize = size(Ysm);
  
  if method == 0
    in = arrayfun(@(i)minRank(i):gridStep:maxRank(i),1:N,'UniformOutput',false);
    out = cell(1,N);
    [out{:}] = ndgrid(in{:});
    out = cell2mat(cellfun(@(i)i(:),out,'UniformOutput',false)); 
  else
    out = repmat(ysize, ysize(method), 1);
    out(:,method) = 1:ysize(method);
  end
  
  %% core complexity measures
  model_elts = @(s)(sum(bsxfun(@times,size(Ysm),s),2)+prod(s,2));
  core_elts = @(s)(prod(s,2));
  core_sum = @(s)(sum(s,2));

  %% error options
  erroptions = struct;
  erroptions.threshold = 0; % usually set to 1
  erroptions.perNeuron = 0;
  
  if verbose;
  disp('r2 / r1'); end

  % replacement?
  if resample
    Ys = resampleTrials(Y, 1);
  end
  
  err = zeros(size(out,1), r1);
  for r2 = 1:r1
    if verbose; disp([num2str(r2) ' / ' num2str(r1)]); end
    Ytrain = Ys(:,:,:,1:r1);
    Ytrain(:,:,:,r2) = [];
    Yval = Ys(:,:,:,r2);
    for ii = 1:size(out,1)     
      % compute error:
      Yhat = tensorDenoiseSVD(mean(Ytrain, 4, 'omitnan'), out(ii,:));
      err(ii,r2) = tensorDenoiseERR( Yval, Yhat, erroptions );
    end
  end
  err_avg = mean(err,2);
  % get mins
  
  %% optimal model -- lots to do
  [p_out, p_complexity, p_err_avg] = pareto(out, core_elts);
  
  % search through possible slope values:
  % f(x) - mx. find min for different choices of m.
  
  minind = find(err_avg == min(err_avg),1);
  minrank = out(minind,:);
  
  Yest = tensorDenoiseSVD(Ysm, minrank);
  
  %% output -- to do
  summary.ranks = out;
  summary.model_elts = model_elts(out);
  summary.core_elts = core_elts(out);
  summary.core_sum = core_sum(out);
  summary.err = err_avg;
  summary.p_err = p_err_avg;
  summary.p_complexity = p_complexity;
  summary.p_ranks = p_out;
  summary.minind = minind;
  summary.minrank = minrank;
  summary.Yest = Yest;
  summary.options = options;
  
  %% function not ready -- pareto optimal ranks
  function [rnks,x,y] = pareto(rnks, coreMeasure)
    %% pareto optimal
    x = coreMeasure(rnks);
    y = err_avg;

    d = sqrt(x.^2+y.^2);
    [d,idx] = sort(d);
    rnks = rnks(idx,:);
    x = x(idx);
    y = y(idx);

    p = 1;
    while sum(p) <= length(x) % originally it was ~=. now it is <=
        idx = (x >= x(p) & y > y(p)) | (x > x(p) & y >= y(p));
        if any(idx)
            rnks = rnks(~idx,:); x = x(~idx); y = y(~idx); d = d(~idx);
        end
        p = p+1-sum(idx(1:p));
    end
    [~,idx] = sortrows([coreMeasure(rnks) -y]);
    rnks = rnks(idx,:); x = x(idx); y = y(idx);
  end

  %% resample trials
  % to do:
  % separate into different function.
  function Yout = resampleTrials( Yin, repl )
      rng(r1+1000*rng_iter);
      trialCount = getTrialCount(Yin);
      for nn = 1:n;
        for cc = 1:c
          % replacement option 1: with replacement
          if repl
            trialInds = randi(trialCount(nn,cc), 1, trialCount(nn,cc));
          % replacement option 2: without replacement
          else
            trialInds = randperm(trialCount(nn,cc));
          end
          Yin(nn,:,cc,1:trialCount(nn,cc)) = Yin(nn,:,cc,trialInds);
        end
      end
      Yout = Yin;
  end

  %% get trial count. used in resampleTrials()
  function trialOut = getTrialCount(Yin)
    [n,t,c,r] = size(Yin);
    for nn = 1:n
      for cc = 1:c
        trialOut(nn,cc) = sum(~isnan(Yin(nn,1,cc,:)));
      end
    end
  end


end