function [ data, g, data0 ] = CartPoleReachability(accuracy)
% cartpole: demonstrate the 3D aircraft collision avoidance example
%
%   [ data, g, data0 ] = cartpole(accuracy)
%
% In this example, the target set is a circle at the origin (cylinder in 3D)
% that represents a collision in relative coordinates between the evader
% (player a, fixed at the origin facing right) and the pursuer (player b).
%
% The relative coordinate dynamics are
%
%   \dot x    = -v_a + v_b \cos \psi + a y
%	  \dot y    = v_b \sin \psi - a x
%	  \dot \psi = b - a
%
% where v_a and v_b are constants, input a is trying to avoid the target
%	input b is trying to hit the target.
%
% For more details, see my PhD thesis, section 3.1.
%
% This function was originally designed as a script file, so most of the
% options can only be modified in the file.  For example, edit the file to
% change the grid dimension, boundary conditions, aircraft parameters, etc.
%
% To get exactly the result from the thesis choose:
%   targetRadius = 5, velocityA = velocityB = 5, inputA = inputB = +1.
%
% Input Parameters:
%
%   accuracy: Controls the order of approximations.
%     'low': Use odeCFL1 and upwindFirstFirst.
%     'medium': Use odeCFL2 and upwindFirstENO2 (default).
%     'high': Use odeCFL3 and upwindFirstENO3.
%     'veryHigh': Use odeCFL3 and upwindFirstWENO5.
%
% Output Parameters:
%
%   data: Implicit surface function at t_max.
%
%   g: Grid structure on which data was computed.
%
%   data0: Implicit surface function at t_0.

% Copyright 2004 Ian M. Mitchell (mitchell@cs.ubc.ca).
% This software is used, copied and distributed under the licensing
%   agreement contained in the file LICENSE in the top directory of
%   the distribution.
%
% Ian Mitchell, 3/26/04
% Subversion tags for version control purposes.
% $Date: 2012-07-04 14:27:00 -0700 (Wed, 04 Jul 2012) $
% $Id: cartpole.m 74 2012-07-04 21:27:00Z mitchell $

%---------------------------------------------------------------------------
% You will see many executable lines that are commented out.
%   These are included to show some of the options available; modify
%   the commenting to modify the behavior.

%---------------------------------------------------------------------------
% Make sure we can see the kernel m-files.
run('addPathToKernel');

%---------------------------------------------------------------------------
% Integration parameters.
tMax = 2;                  % End time.
plotSteps = 9;               % How many intermediate plots to produce?
t0 = 0;                      % Start time.
singleStep = 0;              % Plot at each timestep (overrides tPlot).

% Period at which intermediate plots should be produced.
tPlot = (tMax - t0) / (plotSteps - 1);

% How close (relative) do we need to get to tMax to be considered finished?
small = 100 * eps;

% What kind of dissipation?
dissType = 'global';

%---------------------------------------------------------------------------
% Problem Parameters.

%---------------------------------------------------------------------------

gravity = 9.8;
masscart = 1.0;
masspole = 0.1;
total_mass = (masspole + masscart);
semi_length = 0.5; % actually half the pole's length
polemass_length = (masspole * semi_length);
force_mag = 10.0;
tau = 0.02;


% Create the grid.
g.dim = 4;
x_threshold = 2.4;
theta_threshold = 12*2*pi/360;

x_dot_bound = 2.0;
theta_dot_bound = 50*2*pi/360;
buckets = [100; 20; 20; 20];
g.N = buckets + 2 % needed to add a point in the avoid set
% TODO need to scale appropriately to add one more grid cell of same size
bound = [ x_threshold; x_dot_bound;  theta_threshold; theta_dot_bound]
extended_bound = (2 .* bound ./ g.N) + bound  % one cell is (high-low)/n
g.min = -extended_bound; %state bounds need to add a few states in the target set - NL
g.max = +extended_bound; %state bounds perhaps make 20 degrees
g.bdry = { @addGhostExtrapolate; @addGhostExtrapolate; @addGhostExtrapolate; @addGhostExtrapolate}; % need to use extraploate for all dimensions - NL
% Roughly equal dx in x and y (so different N).

% Need to trim max bound in \psi (since the BC are periodic in this dimension).
g = processGrid(g);

%---------------------------------------------------------------------------
% Create initial conditions (cylinder centered on origin).
target_min = [-x_threshold; -extended_bound(2); -theta_threshold; -extended_bound(4)]
target_max = [+x_threshold; +extended_bound(2); +theta_threshold; +extended_bound(4)]
data = -shapeRectangleByCorners(g, target_min, target_max); % target avoid set use negative shapeRectangle so that stays inside rectangle - NL
data0 = data;

%---------------------------------------------------------------------------
% Set up spatial approximation scheme.
schemeFunc = @termLaxFriedrichs; % numerical approx scheme - NL
schemeData.hamFunc = @cartpoleHamFunc;
schemeData.partialFunc = @cartpolePartialFunc;
schemeData.grid = g;

schemeData.gravity = gravity;
schemeData.masscart = masscart;
schemeData.masspole = masspole;
schemeData.total_mass = total_mass;
schemeData.semi_length = semi_length;
schemeData.polemass_length = polemass_length;
schemeData.force_mag = force_mag;
schemeData.tau = tau;

%---------------------------------------------------------------------------
% Choose degree of dissipation.

switch(dissType)
 case 'global'
  schemeData.dissFunc = @artificialDissipationGLF;
 case 'local'
  schemeData.dissFunc = @artificialDissipationLLF;
 case 'locallocal'
  schemeData.dissFunc = @artificialDissipationLLLF;
 otherwise
  error('Unknown dissipation function %s', dissFunc);
end

%---------------------------------------------------------------------------
if(nargin < 1)
  accuracy = 'medium';
end

% Set up time approximation scheme.
integratorOptions = odeCFLset('factorCFL', 0.75, 'stats', 'on');

% Choose approximations at appropriate level of accuracy.
switch(accuracy)
 case 'low'
  schemeData.derivFunc = @upwindFirstFirst;
  integratorFunc = @odeCFL1;
 case 'medium'
  schemeData.derivFunc = @upwindFirstENO2;
  integratorFunc = @odeCFL2;
 case 'high'
  schemeData.derivFunc = @upwindFirstENO3;
  integratorFunc = @odeCFL3;
 case 'veryHigh'
  schemeData.derivFunc = @upwindFirstWENO5;
  integratorFunc = @odeCFL3;
 otherwise
  error('Unknown accuracy level %s', accuracy);
end

if(singleStep)
  integratorOptions = odeCFLset(integratorOptions, 'singleStep', 'on');
end

%---------------------------------------------------------------------------
% Restrict the Hamiltonian so that reachable set only grows.
%   The Lax-Friedrichs approximation scheme MUST already be completely set up.
innerFunc = schemeFunc;
innerData = schemeData;
clear schemeFunc schemeData;

% Wrap the true Hamiltonian inside the term approximation restriction routine.
schemeFunc = @termRestrictUpdate;
schemeData.innerFunc = innerFunc;
schemeData.innerData = innerData;
schemeData.positive = 0;

%---------------------------------------------------------------------------
% Loop until tMax (subject to a little roundoff).
tNow = t0;
startTime = cputime;
iteration = 0;
while(tMax - tNow > small * tMax)
  fprintf('Iteration: %g', iteration)
  % Reshape data array into column vector for ode solver call.
  y0 = data(:);

  % How far to step?
  tSpan = [ tNow, min(tMax, tNow + tPlot) ];

  % Take a timestep.
  [ t y ] = feval(integratorFunc, schemeFunc, tSpan, y0,...
                  integratorOptions, schemeData);
  tNow = t(end);

  % Get back the correctly shaped data array
  data = reshape(y, g.shape);
  value_function = data;
  pen_grid = g;
  save analytic_data
  %CHANGED: If no significant change, call it converged and quit.
  change_amount = max(abs(y - y0));
  fprintf(' Max change in value function %g\n', change_amount)
  if change_amount < 0.1,
      fprintf(' Converged: Threshold reached.\n')
      break;
  end
  iteration = iteration + 1;
end

endTime = cputime;
fprintf('Total execution time %g seconds\n', endTime - startTime);



%---------------------------------------------------------------------------
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%---------------------------------------------------------------------------
function hamValue = cartpoleHamFunc(t, data, deriv, schemeData)
% cartpoleHamFunc: analytic Hamiltonian for 3D collision avoidance example.
%
% hamValue = cartpoleHamFunc(t, data, deriv, schemeData)
%
% This function implements the hamFunc prototype for the three dimensional
%   aircraft collision avoidance example (also called the game of
%   two identical vehicles).
%
% It calculates the analytic Hamiltonian for such a flow field.
%
% Parameters:
%   t            Time at beginning of timestep (ignored).
%   data         Data array.
%   deriv	 Cell vector of the costate (\grad \phi).
%   schemeData	 A structure (see below).
%
%   hamValue	 The analytic hamiltonian.
%
% schemeData is a structure containing data specific to this Hamiltonian
%   For this function it contains the field(s):
%
%   .grid	 Grid structure.
%   .velocityA	 Speed of the evader (positive constant).
%   .velocityB	 Speed of the pursuer (positive constant).
%   .inputA	 Maximum turn rate of the evader (positive).
%   .inputB	 Maximum turn rate of the pursuer (positive).
%
% Ian Mitchell 3/26/04

grid = schemeData.grid;

% implements equation (3.3) from my thesis term by term
%   with allowances for \script A and \script B \neq [ -1, +1 ]
%   where deriv{i} is p_i
%         x_r is grid.xs{1}, y_r is grid.xs{2}, \psi_r is grid.xs{3}
%         v_a is velocityA, v_b is velocityB,
%         \script A is inputA and \script B is inputB


temp_low = (-schemeData.force_mag + schemeData.polemass_length .* grid.xs{4} .* grid.xs{4} .* sin(grid.xs{3})) ./ schemeData.total_mass;
temp_high = (schemeData.force_mag + schemeData.polemass_length .* grid.xs{4} .* grid.xs{4} .* sin(grid.xs{3})) ./ schemeData.total_mass;
theta_acc_low = (schemeData.gravity .* sin(grid.xs{3}) - cos(grid.xs{3}) .* temp_low) ./ (schemeData.semi_length .* (4.0./3.0 - schemeData.masspole .* cos(grid.xs{3}) .* cos(grid.xs{3}) ./ schemeData.total_mass));
theta_acc_high = (schemeData.gravity .* sin(grid.xs{3}) - cos(grid.xs{3}) .* temp_high) ./ (schemeData.semi_length .* (4.0./3.0 - schemeData.masspole .* cos(grid.xs{3}) .* cos(grid.xs{3}) ./ schemeData.total_mass));
pos_acc_low = temp_low - schemeData.polemass_length .* theta_acc_low .* cos(grid.xs{3}) ./ schemeData.total_mass;
pos_acc_high = temp_high - schemeData.polemass_length .* theta_acc_high .* cos(grid.xs{3}) ./ schemeData.total_mass;
hamValue = (deriv{1} .* grid.xs{2} + deriv{3} .* grid.xs{4} + max(deriv{2} .* pos_acc_high + deriv{4} .* theta_acc_high, deriv{2} .* pos_acc_low + deriv{4} .* theta_acc_low));


%---------------------------------------------------------------------------
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%---------------------------------------------------------------------------
function alpha = cartpolePartialFunc(t, data, derivMin, derivMax, schemeData, dim)
% cartpolePartialFunc: Hamiltonian partial fcn for 3D collision avoidance example.
%
% alpha = cartpolePartialFunc(t, data, derivMin, derivMax, schemeData, dim)
%
% This function implements the partialFunc prototype for the three dimensional
%   aircraft collision avoidance example (also called the game of
%   two identical vehicles).
%
% It calculates the extrema of the absolute value of the partials of the
%   analytic Hamiltonian with respect to the costate (gradient).
%
% Parameters:
%   t            Time at beginning of timestep (ignored).
%   data         Data array.
%   derivMin	 Cell vector of minimum values of the costate (\grad \phi).
%   derivMax	 Cell vector of maximum values of the costate (\grad \phi).
%   schemeData	 A structure (see below).
%   dim          Dimension in which the partial derivatives is taken.
%
%   alpha	 Maximum absolute value of the partial of the Hamiltonian
%		   with respect to the costate in dimension dim for the
%                  specified range of costate values (O&F equation 5.12).
%		   Note that alpha can (and should) be evaluated separately
%		   at each node of the grid.
%
% schemeData is a structure containing data specific to this Hamiltonian
%   For this function it contains the field(s):
%
%   .grid	 Grid structure.
%   .velocityA	 Speed of the evader (positive constant).
%   .velocityB	 Speed of the pursuer (positive constant).
%   .inputA	 Maximum turn rate of the evader (positive).
%   .inputB	 Maximum turn rate of the pursuer (positive).
%
% Ian Mitchell 3/26/04

grid = schemeData.grid;
temp_low = (-schemeData.force_mag + schemeData.polemass_length .* grid.xs{4} .* grid.xs{4} .* sin(grid.xs{3})) ./ schemeData.total_mass;
temp_high = (schemeData.force_mag + schemeData.polemass_length .* grid.xs{4} .* grid.xs{4} .* sin(grid.xs{3})) ./ schemeData.total_mass;
theta_acc_low = (schemeData.gravity .* sin(grid.xs{3}) - cos(grid.xs{3}) .* temp_low) ./ (schemeData.semi_length .* (4.0./3.0 - schemeData.masspole .* cos(grid.xs{3}) .* cos(grid.xs{3}) ./ schemeData.total_mass));
theta_acc_high = (schemeData.gravity .* sin(grid.xs{3}) - cos(grid.xs{3}) .* temp_high) ./ (schemeData.semi_length .* (4.0./3.0 - schemeData.masspole .* cos(grid.xs{3}) .* cos(grid.xs{3}) ./ schemeData.total_mass));
pos_acc_low = temp_low - schemeData.polemass_length .* theta_acc_low .* cos(grid.xs{3}) ./ schemeData.total_mass;
pos_acc_high = temp_high - schemeData.polemass_length .* theta_acc_high .* cos(grid.xs{3}) ./ schemeData.total_mass;
alpha = (abs(grid.xs{2} + grid.xs{4}) + max(abs(pos_acc_high + theta_acc_high), abs(pos_acc_low + theta_acc_low)));
