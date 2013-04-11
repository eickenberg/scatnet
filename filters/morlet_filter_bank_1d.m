%TODO redo doc
%MORLET_FILTER_BANK Calculates a Morlet/Gabor filter bank
%   filters = morlet_filter_bank(sig_length,options) generates a Morlet or 
%   Gabor filter bank for signals of length sig_length using parameters
%   contained in options. If the number of wavelets per octave specified
%   exceeds 1, the convential (logarithimically spaced, constant-Q) wavelets
%   will be supplemented by linarly spaced, contant-bandwidth filters in 
%   the low frequencies in order to adequately cover the frequency domain
%   without increasing the temporal support of the filters.
%
%   The following options can be specified:
%      options.Q - The number of wavelets per octave at critical sampling in
%         frequency. [Default 1]
%      options.a - The dilation factor between adjacent wavelets. The factor
%         2^(1/Q) corresponds to critical sampling. More redundant frequency
%         sampling can be obtained by decreasing a. [Default 2^(1/Q)]
%      options.J - The number of logarithmically spaced wavelets. This
%         controls the minimum frequency bandwidth of the wavelets and 
%         consequently the maximum temporal bandwidth. For a filter bank
%         with parameters Q, a, J, the maximum temporal bandwidth is Q*a^J.
%         [Default log(sig_length/Q)/log(a)]
%      options.gabor - If 0, Morlet wavelets are used, whereas if 1, Gabor
%         filters are used. Since the former have a vanishing moment, they are
%         highly recommended. For audio signals, however, energy at very low
%         frequencies is often small, so Gabor filters can be used in the
%         first-order filter bank. [Default 0]
%      options.precision - The precision, 'double' or 'single', used to define 
%         the filters. [Default 'double']
%      options.optimize - The optimization technique used to store the
%         filters. If set to 'none', filters are stored using their full
%         Fourier transform. If 'periodize', filters are periodized to create
%         Fourier transform at lower resolutions. Finally, if 'truncate', 
%         the Fourier transform of the filter is truncated and its support is
%         stored. [Default 'truncate']
%
%   The output, a structure, contains the wavelet filters (psi) in a cell
%   array and lowpass filter (phi). Each filter is stored according to the 
%   optimization technique specified in options.optimize. In addition, the
%   parameters used to define filters are stored, as well as information on
%   the center and bandwidth of each filter.

function filters = morlet_filter_bank_1d(sig_length,options)    
	if nargin < 2
		options = struct();
	end

	parameter_fields = {'V','J','P','sigma_psi','sigma_phi','gabor'};

	% If we are given a two-dimensional size, take first dimension
	sig_length = sig_length(1);
	
	sigma0 = 2/sqrt(3);

	% Fill in default parameters
	options = fill_struct(options, ...
		'V', 1);
	options = fill_struct(options, ...
		'xi_psi',1/2*(2^(-1/options.V)+1)*pi);
	options = fill_struct(options, ...
		'sigma_psi',1/2*sigma0/(1-2^(-1/options.V)));
	options = fill_struct(options, ...
		'B_phi', 2);
	options = fill_struct(options, ...
		'sigma_phi', options.sigma_psi/options.B_phi);
	options = fill_struct(options, ...
		'J', floor(log2(sig_length/(options.sigma_psi/sigma0))*options.V));
	options = fill_struct(options, ...
		'P', round(2*2^(-1/options.V)*(options.sigma_psi/sigma0)-1/2*options.sigma_psi/options.sigma_phi));
	options = fill_struct(options, ...
		'gabor', 0);
	options = fill_struct(options, ...
		'precision', 'double');
	options = fill_struct(options, ...
		'optimize', 'fourier_truncated');

	filters = struct();

	% Copy filter parameters into filter structure. This is needed by the
	% scattering algorithm to calculate sampling, path space, etc.
	for l = 1:length(parameter_fields)
		filters = setfield(filters,parameter_fields{l}, ...
			getfield(options,parameter_fields{l}));
	end

	% Calculate center frequency and standard deviation for mother wavelet
	% these should reduce to 3*pi/4 and sqrt(3)/2, respectively, for the case
	% Q = 1 (why?)
	%psi_xi = 0.5*(2^(-1/options.V)+1)*pi;
	%psi_bw = ((2^(1/options.Q)-1)/(2^(1/options.Q)+1)*3)*psi_xi/(3*pi/4)*pi;
	%psi_sigma = (sqrt(3)/2)*psi_bw/pi;

	% Calculate the standard deviation for the scaling function
	%phi_bw = psi_bw;
	%phi_sigma = 2*psi_sigma;

	% The normalization factor for the wavelets, calculated using the filters
	% at the finest resolution (N)
	psi_ampl = 1;

	N = sig_length;
	
	filters.N = N;
	
	filters.psi = cell(1,options.J+options.P);
	filters.phi = [];

	% Calculate logarithmically spaced filters.
	for j1 = 0:options.J-1
		psi_center(j1+1) = options.xi_psi*2^(-j1/options.V);
		psi_sigma(j1+1) = options.sigma_psi*2^(j1/options.V);
	end

	% Calculate linearly spaced filters so that they evenly cover the
	% remaining part of the spectrum
	step = pi*2^(-options.J/options.V)*(1-1/4*sigma0/options.sigma_phi*2^(1/options.V))/options.P;
	for k1 = 0:options.P-1
		psi_center(options.J+k1+1) = ...
			options.xi_psi*2^((-options.J+1)/options.V)-step*(k1+1);
		psi_sigma(options.J+k1+1) = options.sigma_psi*2^((options.J-1)/options.V);
	end

	% Calculate normalization of filters so that sum of squares does not 
	% exceed 2. This guarantees that the scattering transform is
	% contractive.
	S = zeros(N,1);

	% As it occupies a larger portion of the spectrum, it is more
	% important for the logarithmic portion of the filter bank to be
	% properly normalized, so we only sum their contributions.
	for j1 = 0:options.J-1
		temp = gabor(N,psi_center(j1+1),psi_sigma(j1+1),options.precision);
		if ~options.gabor
			temp = morletify(temp,psi_sigma(j1+1));
		end
		S = S+abs(temp).^2;
	end

	psi_ampl = sqrt(2/max(S));

	% Apply the normalization factor to the filters.
	for j1 = 0:length(filters.psi)-1
		temp = gabor(N,psi_center(j1+1),psi_sigma(j1+1),options.precision);
		if ~options.gabor
			temp = morletify(temp,psi_sigma(j1+1)); 
		end
		filters.psi{j1+1} = psi_ampl*temp;
		filters.psi{j1+1} = optimize_filter(filters.psi{j1+1},0,options);
	end

	% Calculate the associated low-pass filter
	filters.phi = gabor(N, 0, ...
		options.sigma_phi*2^((options.J-1)/options.V), ...
		options.precision); 

	filters.phi = optimize_filter(filters.phi,1,options);

	filters.type = 'morlet_1d';
end

function f = gabor(N,xi,sigma,precision)
	extent = 1;         % extent of periodization - the higher, the better

	sigma = 1/sigma;

	f = zeros(N,1,precision);

	% Calculate the 2*pi-periodization of the filter over 0 to 2*pi*(N-1)/N
	for k = -extent:1+extent
		f = f+exp(-(([0:N-1].'-k*N)/N*2*pi-xi).^2./(2*sigma^2));
	end
end

function f = morletify(f,sigma)
	f0 = f(1);

	f = f-f0*gabor(length(f),0,sigma,class(f));
end