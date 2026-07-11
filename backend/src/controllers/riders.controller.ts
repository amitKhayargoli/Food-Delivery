import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';
import { notifyUser } from '../services/fcm.service';

// ──────────────────────────────────────────────
// POST /api/riders/apply
// Submit a delivery partner application
// ──────────────────────────────────────────────
export const applyForRider = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const {
      full_name,
      email,
      phone,
      vehicle_type,
      vehicle_number,
      license_url,
      profile_image_url,
    } = req.body;

    // Validate required fields
    const required = ['full_name', 'email', 'phone', 'vehicle_type', 'vehicle_number', 'license_url'];
    const missing = required.filter((f) => !req.body[f]);
    if (missing.length > 0) {
      res.status(400).json({ error: `Missing required fields: ${missing.join(', ')}` });
      return;
    }

    // Check if user already has a pending/approved application
    const { data: existing } = await supabase.admin
      .from('rider_applications')
      .select('id, status')
      .eq('user_id', userId)
      .in('status', ['PENDING', 'APPROVED'])
      .limit(1)
      .maybeSingle();

    if (existing) {
      res.status(409).json({
        error: `You already have an ${existing.status.toLowerCase()} application.`,
        status: existing.status,
      });
      return;
    }

    const { data: application, error } = await supabase.admin
      .from('rider_applications')
      .insert({
        user_id: userId,
        full_name,
        email,
        phone,
        vehicle_type,
        vehicle_number,
        license_url: license_url,
        profile_image_url: profile_image_url || null,
        status: 'PENDING',
      })
      .select('id, full_name, status, created_at')
      .single();

    if (error) {
      console.error('[RiderApplication] Insert error:', error);
      res.status(500).json({ error: 'Failed to submit application.' });
      return;
    }

    // Notify admin about the new application
    const { data: admins } = await supabase.admin
      .from('users')
      .select('id')
      .contains('roles', ['ADMIN']);

    if (admins) {
      for (const admin of admins) {
        notifyUser(admin.id, supabase.admin, {
          title: 'New Rider Application 🚴',
          body: `${full_name} has applied to become a delivery partner.`,
          data: {
            type: 'rider_application',
            application_id: application.id,
          },
        }, 'admin');
      }
    }

    res.status(201).json({
      message: 'Application submitted successfully. Awaiting admin review.',
      application,
    });
  } catch (error) {
    console.error('[RiderApplication] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/riders/apply/my
// Get the current user's rider application
// ──────────────────────────────────────────────
export const getMyRiderApplication = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: application, error } = await supabase.admin
      .from('rider_applications')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error('[RiderApplication] Fetch error:', error);
      res.status(500).json({ error: 'Failed to fetch application.' });
      return;
    }

    res.status(200).json({ application });
  } catch (error) {
    console.error('[RiderApplication] Get my error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/riders/apply
// Get all pending rider applications (admin only)
// ──────────────────────────────────────────────
export const getAllRiderApplications = async (_req: Request, res: Response): Promise<void> => {
  try {
    const { data: applications, error } = await supabase.admin
      .from('rider_applications')
      .select('*, users(username, email, phone)')
      .eq('status', 'PENDING')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[RiderApplication] Fetch all error:', error);
      res.status(500).json({ error: 'Failed to fetch applications.' });
      return;
    }

    res.status(200).json(applications);
  } catch (error) {
    console.error('[RiderApplication] Get all error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/riders/apply/:id/status
// Approve or reject a rider application (admin only)
// ──────────────────────────────────────────────
export const updateRiderApplicationStatus = async (req: Request, res: Response): Promise<void> => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    const validStatuses = ['APPROVED', 'REJECTED'];
    if (!validStatuses.includes(status)) {
      res.status(400).json({ error: `Status must be one of: ${validStatuses.join(', ')}` });
      return;
    }

    // Fetch the application
    const { data: application, error: fetchError } = await supabase.admin
      .from('rider_applications')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (fetchError || !application) {
      res.status(404).json({ error: 'Application not found.' });
      return;
    }

    if (application.status !== 'PENDING') {
      res.status(409).json({ error: `Application has already been ${application.status.toLowerCase()}.` });
      return;
    }

    // Update the application status
    const { data: updated, error: updateError } = await supabase.admin
      .from('rider_applications')
      .update({ status })
      .eq('id', id)
      .select('id, full_name, status')
      .single();

    if (updateError) {
      console.error('[RiderApplication] Status update error:', updateError);
      res.status(500).json({ error: 'Failed to update application status.' });
      return;
    }

    // If approved, grant the user DELIVERY_BOY role
    if (status === 'APPROVED' && application.user_id) {
      console.log(`[RT-BACKEND] 🎉 Approving rider application for user ${application.user_id}`);

      const { data: userData } = await supabase.admin
        .from('users')
        .select('roles')
        .eq('id', application.user_id)
        .maybeSingle();

      const currentRoles: string[] = userData?.roles || ['CUSTOMER'];
      if (!currentRoles.includes('DELIVERY_BOY')) {
        currentRoles.push('DELIVERY_BOY');
      }

      const { error: roleError } = await supabase.admin
        .from('users')
        .update({
          role: 'DELIVERY_BOY',
          roles: currentRoles,
          status: 'ACTIVE',
        })
        .eq('id', application.user_id);

      if (roleError) {
        console.error('[RT-BACKEND] ❌ User role update error:', roleError);
      } else {
        console.log(`[RT-BACKEND] ✅ User ${application.user_id} roles updated — added DELIVERY_BOY`);

        // Send push notification to the user
        notifyUser(application.user_id, supabase.admin, {
          title: 'Application Approved 🎉',
          body: 'Your delivery partner application has been approved! You now have rider access.',
          data: {
            type: 'role_change',
            role: 'DELIVERY_BOY',
          },
        }, 'rider');
      }
    }

    // Send rejection notification
    if (status === 'REJECTED' && application.user_id) {
      console.log(`[RT-BACKEND] ❌ Rejected rider application for user ${application.user_id}`);
      notifyUser(application.user_id, supabase.admin, {
        title: 'Application Update',
        body: 'Your delivery partner application could not be approved at this time.',
        data: {
          type: 'role_change',
          role: 'CUSTOMER',
        },
      }, 'rider');
    }

    res.status(200).json({
      message: `Application ${status.toLowerCase()} successfully.`,
      application: updated,
    });
  } catch (error) {
    console.error('[RiderApplication] Status update error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
