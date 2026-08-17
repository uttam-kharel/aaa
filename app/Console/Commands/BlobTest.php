<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

class BlobTest extends Command
{
    protected $signature = 'blob:test';

    protected $description = 'Verify the Vercel Blob store by uploading, reading and deleting a test file via the s3 disk';

    public function handle(): int
    {
        $disk = Storage::disk('s3');
        $path = 'codebuff-test/hello.txt';

        try {
            $this->line("\n[1/4] Uploading...");
            $disk->put($path, 'Hello from '.config('app.name'));
            $this->line('  uploaded: '.$path);

            $this->line('[2/4] Reading back...');
            $this->line('  contents: '.$disk->get($path));

            $this->line('[3/4] Public URL...');
            $url = $disk->url($path);
            $this->line('  url: '.$url);
            if (str_contains($url, 'amazonaws.com')) {
                $this->warn('  AWS_URL is not set — Storage::url() is producing a default S3 URL.');
                $this->warn('  Set AWS_URL to https://<store-id>.public.blob.vercel-storage.com in Vercel.');
            }

            $this->line('[4/4] Deleting...');
            $disk->delete($path);
            $this->line('  deleted '.$path);
        } catch (\Throwable $e) {
            $this->error($e->getMessage());

            return self::FAILURE;
        }

        $this->newLine();
        $this->info('Vercel Blob is working. ✔');

        return self::SUCCESS;
    }
}
