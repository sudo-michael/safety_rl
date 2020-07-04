"""
This file is a modified version of Ray's implementation of Policy Gradient (PG) which can
be found @
https://github.com/ray-project/ray/blob/releases/0.7.3/python/ray/rllib/agents/pg/pg_policy.py

This file is modified such that PG can be used with the Safety Bellman Equation (SBE) outcome from
equation (8) in [ICRA19]. All modifications are marked with a line of hashtags.

Authors: Neil Lugovoy   ( nflugovoy@berkeley.edu )

See the LICENSE in the root directory of this repo for license info.
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import ray
from ray.rllib.evaluation.postprocessing import Postprocessing
from ray.rllib.policy.tf_policy_template import build_tf_policy
from ray.rllib.policy.sample_batch import SampleBatch
from ray.rllib.utils import try_import_tf
###########################################################
# import function to compute SBE advantages induced by SBE outcome from Equation (8) of [ICRA19]
#  instead of sum of discounted rewards advantages
from policy_gradient.postprocessing import compute_advantages
###########################################################
tf = try_import_tf()


# The basic policy gradients loss
def policy_gradient_loss(policy, model, dist_class, train_batch):
    logits, _ = model.from_batch(train_batch)
    action_dist = dist_class(logits, model)
    return -tf.reduce_mean(
        action_dist.logp(train_batch[SampleBatch.ACTIONS]) *
        train_batch[Postprocessing.ADVANTAGES])


# This adds the "advantages" column to the sampletrain_batch.
def postprocess_advantages(policy,
                           sample_batch,
                           other_agent_batches=None,
                           episode=None):
    ###########################################################
    # compute advantages by using trajectory outcome from Equation (8) of [ICRA19]
    return compute_advantages(sample_batch, 0.0, policy.config["gamma"],
                              use_gae=False, use_sbe=True)
    ###########################################################


PGTFPolicy = build_tf_policy(
    name="PGTFPolicy",
    get_default_config=lambda: ray.rllib.agents.pg.pg.DEFAULT_CONFIG,
    postprocess_fn=postprocess_advantages,
    loss_fn=policy_gradient_loss)